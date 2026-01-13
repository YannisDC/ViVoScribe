@preconcurrency import AVFoundation
import Accelerate
import CoreAudio
import OSLog
import FluidAudio

actor AudioInput {
    private let logger = Logging(name: "AudioInput")
    private var audioEngine: AVAudioEngine?
    private var targetDeviceID: AudioDeviceID?
    private let minBufferLength = 4096
    private let audioConverter = AudioConverter()

    private var callbackHandler: @Sendable (TranscriptionAudioBuffer) async -> Void = { _ in }
    private var isMuted: Bool = false

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }

    init() {}

    func configure(deviceID: AudioDeviceID) {
        targetDeviceID = deviceID
    }

    func startRecording(
        onAudioBuffer: @escaping @Sendable (TranscriptionAudioBuffer) -> Void
    ) async throws {
        callbackHandler = onAudioBuffer

        guard let deviceID = targetDeviceID else {
            let error = NSError(
                domain: "AudioInput",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "No audio device configured"]
            )
            throw error
        }

        logger.info("Starting microphone input for device: \(deviceID)")

        await stopRecording()

        let maxAttempts = 3
        let delays: [UInt64] = [500_000_000, 1_000_000_000] // 0.5s, 1.0s in nanoseconds
        var lastError: Error?

        for attempt in 1...maxAttempts {
            logger.info("Attempting to start recording (attempt \(attempt)/\(maxAttempts))")

            do {
                audioEngine = try await setupAudioEngine(deviceID: deviceID)
                logger.info("Microphone input started successfully")
                return
            } catch {
                lastError = error
                logger.info("Recording start attempt \(attempt) failed: \(error)")

                // If not the last attempt, wait before retrying
                if attempt < maxAttempts {
                    await stopRecording()
                    try? await Task.sleep(nanoseconds: delays[attempt - 1])
                }
            }
        }

        // All attempts failed
        let error = NSError(
            domain: "AudioInput",
            code: 1004,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to start recording after \(maxAttempts) attempts",
                NSUnderlyingErrorKey: lastError as Any
            ]
        )
        throw error
    }

    func stopRecording() async {
        logger.info("Stopping microphone input")

        audioEngine?.attachedNodes.forEach { node in
            node.removeTap(onBus: 0)
        }

        audioEngine?.stop()
        audioEngine = nil

        // 200ms delay for CoreAudio cleanup
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func setupAudioEngine(deviceID: AudioDeviceID) async throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        try await assignAudioDevice(inputNode: inputNode, deviceID: deviceID)

        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        // Target format: 16kHz mono Float32 for FluidAudio
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let bufferSize = AVAudioFrameCount(4096)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { @Sendable
            [weak self] buffer, time in
            guard let self = self else { return }

            Task { @Sendable in
                // Check if muted - early return if so
                guard await !self.isMuted else { return }

                // Convert to 16kHz mono before sending to transcriber
                let convertedBuffer: AVAudioPCMBuffer
                do {
                    let samples = try await self.audioConverter.resampleBuffer(buffer)

                    // Create 16kHz buffer from converted samples
                    guard let pcmBuffer = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: AVAudioFrameCount(samples.count)
                    ) else { return }

                    pcmBuffer.frameLength = AVAudioFrameCount(samples.count)
                    guard let channelData = pcmBuffer.floatChannelData else { return }

                    // Copy samples to buffer
                    for (i, sample) in samples.enumerated() {
                        channelData[0][i] = sample
                    }

                    convertedBuffer = pcmBuffer
                } catch {
                    self.logger.error("Audio conversion failed: \(error)")
                    return
                }

                // Send 16kHz buffer to transcriber
                let transcriptionBuffer = TranscriptionAudioBuffer(
                    buffer: convertedBuffer,
                    timestamp: time.hostTime,
                    source: .microphone
                )

                await self.callbackHandler(transcriptionBuffer)
            }
        }

        engine.prepare()

        // Add 50ms delay to prevent race conditions
        try await Task.sleep(for: .milliseconds(50))

        try engine.start()

        return engine
    }

    private func assignAudioDevice(inputNode: AVAudioInputNode, deviceID: AudioDeviceID) async throws {
        guard let audioUnit = inputNode.audioUnit else {
            let error = NSError(
                domain: "AudioInput",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Audio unit not available"]
            )
            throw error
        }

        let maxAttempts = 3
        let delays: [UInt64] = [100_000_000, 200_000_000, 300_000_000] // 100ms, 200ms, 300ms in nanoseconds

        for attempt in 1...maxAttempts {
            logger.info("Attempting to assign audio device (attempt \(attempt)/\(maxAttempts))")

            var deviceId = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceId,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )

            if status == noErr {
                logger.info("Audio device assigned successfully: \(deviceID)")
                return
            }

            logger.info("Device assignment attempt \(attempt) failed with status: \(status)")

            // If not the last attempt, wait before retrying
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: delays[attempt - 1])
            }
        }

        // All attempts failed
        let error = NSError(
            domain: "AudioInput",
            code: 1002,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to assign audio device after \(maxAttempts) attempts",
                "deviceID": deviceID
            ]
        )
        throw error
    }


    private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameLength = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        let sum = samples.reduce(0) { $0 + abs($1) }
        return sum / Float(frameLength)
    }

    private func getSilenceThreshold() -> Float {
        // Use device-aware thresholds like the reference implementation
        guard let deviceID = targetDeviceID else { return 0.6 }

        let isBluetooth = deviceID.isBluetoothDevice()

        if isBluetooth {
            // Bluetooth devices (AirPods, etc.) - higher threshold to filter noise
            return 0.7
        } else {
            // Regular wired/built-in microphones - medium threshold
            return 0.6
        }
    }

    // MARK: - Mute Control
    func setMuted(_ muted: Bool) {
        isMuted = muted
        logger.info("Microphone muted: \(muted)")
    }

    func toggleMute() {
        isMuted = !isMuted
        logger.info("Microphone muted: \(isMuted)")
    }

    func isMicrophoneMuted() -> Bool {
        return isMuted
    }

}

struct TranscriptionAudioBuffer: Sendable {
    nonisolated let buffer: AVAudioPCMBuffer
    let timestamp: UInt64
    let source: AudioSource

    enum AudioSource {
        case microphone
        case appAudio(processID: pid_t)
        case fileAudio
    }
}

enum TranscriptionError: Error, LocalizedError {
    case noAudioDevice
    case audioFormatNotSupported
    case audioUnitNotAvailable
    case audioDeviceSetupFailed(OSStatus)
    case bufferCreationFailed
    case audioConversionFailed

    // ApplicationAudio errors
    case tapNotActivated
    case invalidChannelCount
    case processTapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case audioDeviceStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noAudioDevice:
            return "No audio device specified"
        case .audioFormatNotSupported:
            return "Audio format not supported"
        case .audioUnitNotAvailable:
            return "Audio unit not available"
        case .audioDeviceSetupFailed(let status):
            return "Audio device setup failed with status: \(status)"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .audioConversionFailed:
            return "Audio conversion failed"
        case .tapNotActivated:
            return "Process tap not activated"
        case .invalidChannelCount:
            return "Invalid audio channel count"
        case .processTapCreationFailed(let status):
            return "Process tap creation failed with status: \(status)"
        case .aggregateDeviceCreationFailed(let status):
            return "Aggregate device creation failed with status: \(status)"
        case .ioProcCreationFailed(let status):
            return "I/O proc creation failed with status: \(status)"
        case .audioDeviceStartFailed(let status):
            return "Audio device start failed with status: \(status)"
        }
    }
}

// AudioDeviceID extensions
extension AudioDeviceID {
    nonisolated func isBluetoothDevice() -> Bool {
        // First, validate the device ID exists and is accessible
        guard isValidDevice() else {
            return false
        }

        // Try to detect Bluetooth via transport type first (safer)
        if let transportType = getTransportType() {
            return transportType == kAudioDeviceTransportTypeBluetooth
        }

        // Fallback to name-based detection if transport type unavailable
        do {
            let deviceName = try getDeviceName()
            let lowercased = deviceName.lowercased()
            return lowercased.contains("bluetooth") ||
                   lowercased.contains("airpods") ||
                   lowercased.contains("beats") ||
                   lowercased.contains("wireless")
        } catch {
            // If we can't get device info, assume it's not Bluetooth for safety
            return false
        }
    }

    private nonisolated func getTransportType() -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if transport type property exists
        guard AudioObjectHasProperty(AudioObjectID(self), &address) else {
            return nil
        }

        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        var transportType: UInt32 = 0

        let status = AudioObjectGetPropertyData(
            AudioObjectID(self),
            &address,
            0,
            nil,
            &dataSize,
            &transportType
        )

        return status == noErr ? transportType : nil
    }

    private nonisolated func isValidDevice() -> Bool {
        // Check if device exists in the system
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if the property exists before trying to access it
        let hasProperty = AudioObjectHasProperty(AudioObjectID(self), &address)
        return hasProperty
    }

    private nonisolated func getDeviceName() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(self), &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else { throw AudioError.propertyNotFound }

        // Use direct CFString approach for safety
        var cfString: CFString?
        let dataStatus = withUnsafeMutablePointer(to: &cfString) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(self),
                &address,
                0,
                nil,
                &dataSize,
                pointer
            )
        }

        guard dataStatus == noErr, let deviceName = cfString else {
            throw AudioError.propertyNotFound
        }

        return deviceName as String
    }
}