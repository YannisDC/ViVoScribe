import Foundation
import AVFoundation
import ScreenCaptureKit
import FluidAudio
import CoreGraphics

/// Captures per-process audio using ScreenCaptureKit
/// Manages multiple SCStreams with 5-second grace period for process lifecycle
actor ApplicationAudio {
    private let logger = Logging(name: "ApplicationAudio")

    // Active streams per process
    private var activeStreams: [pid_t: SCStream] = [:]

    // Stream output handlers per process
    private var outputHandlers: [pid_t: StreamOutputHandler] = [:]

    // Audio converter (reusable across all streams)
    private let audioConverter = AudioConverter()

    // Callback to transcriber
    private var callbackHandler: (@Sendable (TranscriptionAudioBuffer) async -> Void)?

    // Activation state
    private var isActivated = false

    // MARK: - Lifecycle

    func activate() async throws {
        guard !isActivated else {
            logger.info("ApplicationAudio already activated")
            return
        }

        logger.info("Activating per-process audio capture")
        isActivated = true
        logger.info("✅ Per-process audio capture activated")
    }

    func deactivate() async {
        guard isActivated else {
            logger.info("ApplicationAudio not activated")
            return
        }

        logger.info("Deactivating per-process audio capture")

        // Stop all streams
        for (processID, stream) in activeStreams {
            logger.info("Stopping stream for process \(processID)")
            try? await stream.stopCapture()
        }

        // Safety delay before clearing all state to prevent race conditions
        try? await Task.sleep(for: .milliseconds(200))

        activeStreams.removeAll()
        outputHandlers.removeAll()

        isActivated = false
        logger.info("✅ Per-process audio capture deactivated")
    }

    // MARK: - Audio Capture

    func startCapture(
        onAudioBuffer: @escaping @Sendable (TranscriptionAudioBuffer) async -> Void
    ) async throws {
        guard isActivated else {
            throw TranscriptionError.tapNotActivated
        }

        logger.info("Starting audio capture - ready for process streams")
        callbackHandler = onAudioBuffer
    }

    // MARK: - Process Lifecycle

    /// Called when a new process with audio starts (from AudioProcess)
    func handleProcessStarted(process: AudioProcess) async throws {
        let processID = process.id

        // Check if stream already exists
        if activeStreams[processID] != nil {
            logger.info("[\(processID)] Stream already exists")
            return
        }

        // Get SCShareableContent - use onScreenWindowsOnly: false for minimized/hidden apps
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )

        // Try to find by exact PID first
        var scApp = content.applications.first(where: { $0.processID == process.id })

        // If not found and this is a helper process, try to find parent app
        if scApp == nil && process.isHelperProcess {
            let parentName = process.name.replacingOccurrences(of: " Helper", with: "")
                                        .replacingOccurrences(of: " Renderer", with: "")
                                        .replacingOccurrences(of: " GPU", with: "")
                                        .trimmingCharacters(in: .whitespaces)

            logger.info("[\(processID)] Helper process detected, looking for parent: \(parentName)")

            scApp = content.applications.first { app in
                app.applicationName.lowercased().contains(parentName.lowercased())
            }

            if let foundApp = scApp {
                logger.info("[\(processID)] ✅ Mapped helper to parent: \(foundApp.applicationName)")
            }
        }

        // If still not found, log error
        guard let application = scApp else {
            logger.error("[\(processID)] Could not find SCRunningApplication for \(process.name)")
            throw TranscriptionError.audioFormatNotSupported
        }

        // Create stream using existing content
        try await createStream(for: application, content: content)
    }

    /// Called when a new process with audio starts (from SCRunningApplication)
    func handleProcessStarted(application: SCRunningApplication) async throws {
        let processID = application.processID

        // Check if stream already exists
        if activeStreams[processID] != nil {
            logger.info("[\(processID)] Stream already exists")
            return
        }

        // Create new stream
        try await createStream(for: application)
    }

    /// Called when a process stops producing audio
    func handleProcessStopped(processID: pid_t) async {
        logger.info("[\(processID)] Process stopped - cleaning up stream immediately")
        await cleanupStream(processID: processID)
    }

    // MARK: - Stream Management

    private func createStream(
        for application: SCRunningApplication,
        content: SCShareableContent? = nil
    ) async throws {
        let processID = application.processID

        logger.info("[\(processID)] Creating SCStream for: \(application.applicationName)")

        // Use provided content or fetch new (include all windows, even if minimized/hidden)
        let shareableContent: SCShareableContent
        if let content = content {
            shareableContent = content
        } else {
            shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        }

        // Find windows for this application
        let appWindows = shareableContent.windows.filter { $0.owningApplication == application }

        // Need at least one window to capture audio
        guard let window = appWindows.first else {
            logger.info("[\(processID)] No windows found for \(application.applicationName) - skipping stream creation")
            return
        }

        // Create content filter
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Configure stream (audio-only)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48000  // Capture high quality, convert to 16kHz later
        configuration.channelCount = 2     // Stereo

        // Minimal video settings (required but not used)
        configuration.width = 1
        configuration.height = 1
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3

        // Create stream output handler
        let handler = StreamOutputHandler(
            processID: processID,
            audioConverter: audioConverter,
            callback: callbackHandler,
            logger: logger
        )

        // Create stream
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: nil
        )

        // Add audio output
        do {
            try stream.addStreamOutput(
                handler,
                type: SCStreamOutputType.audio,
                sampleHandlerQueue: DispatchQueue(
                    label: "com.e.audio.\(processID)",
                    qos: .userInteractive
                )
            )
        } catch {
            logger.error("[\(processID)] Failed to add stream output: \(error)")
            throw TranscriptionError.audioFormatNotSupported
        }

        // Start capture with retry logic - ScreenCaptureKit can fail transiently
        var retryCount = 0
        var lastError: Error?

        repeat {
            do {
                let bid = Bundle.main.bundleIdentifier ?? "nil"
                let exe = CommandLine.arguments.first ?? "nil"
                logger.info("[\(processID)] Attempt \(retryCount + 1) - preflight=\(CGPreflightScreenCaptureAccess()) bid=\(bid) exe=\(exe)")

                try await stream.startCapture()
                logger.info("[\(processID)] ✅ Stream started")
                lastError = nil
                break
            } catch {
                lastError = error
                retryCount += 1
                logger.info("[\(processID)] Failed to start capture (attempt \(retryCount)/3): \(error)")

                if retryCount < 3 {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms exponential backoff
                }
            }
        } while retryCount < 3 && lastError != nil

        if let error = lastError {
            logger.error("[\(processID)] Failed to start capture after 3 attempts: \(error)")
            throw TranscriptionError.audioFormatNotSupported
        }

        // Store stream and handler
        activeStreams[processID] = stream
        outputHandlers[processID] = handler
    }

    private func cleanupStream(processID: pid_t) async {
        guard let stream = activeStreams[processID] else {
            logger.info("[\(processID)] No stream to cleanup")
            return
        }

        logger.info("[\(processID)] Cleaning up stream")

        // Stop stream (destroys the tap)
        do {
            try await stream.stopCapture()

            // Safety delay after stopping to allow ScreenCaptureKit cleanup
            // Prevents race conditions during rapid stream creation/destruction
            try? await Task.sleep(for: .milliseconds(200))
        } catch {
            logger.error("[\(processID)] Error stopping stream: \(error)")
        }

        // Remove from tracking (all associated resources)
        activeStreams[processID] = nil
        outputHandlers[processID] = nil

        logger.info("[\(processID)] ✅ Stream cleaned up")
    }

    // MARK: - Diagnostics

    func getActiveStreamCount() -> Int {
        return activeStreams.count
    }

    func getActiveProcessIDs() -> [pid_t] {
        return Array(activeStreams.keys)
    }
}

// MARK: - Stream Output Handler

private actor StreamOutputHandler: NSObject, SCStreamOutput {
    private let processID: pid_t
    private let audioConverter: AudioConverter
    private let callback: (@Sendable (TranscriptionAudioBuffer) async -> Void)?
    private let logger: Logging

    // Timestamp deduplication
    private var lastProcessedTime: UInt64 = 0
    private let timeToleranceNanos: UInt64 = 1_000_000  // 1ms tolerance

    init(
        processID: pid_t,
        audioConverter: AudioConverter,
        callback: (@Sendable (TranscriptionAudioBuffer) async -> Void)?,
        logger: Logging
    ) {
        self.processID = processID
        self.audioConverter = audioConverter
        self.callback = callback
        self.logger = logger
        super.init()
    }

    // MARK: - SCStreamOutput Delegate

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }

        // Process audio asynchronously (don't block audio thread)
        Task { [weak self] in
            await self?.handleAudioSample(sampleBuffer)
        }
    }

    // MARK: - Audio Processing

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) async {
        guard let callback = callback else { return }

        let timestamp = mach_absolute_time()

        // Prevent duplicates and super old buffers, allow slight timing jitter
        if timestamp <= lastProcessedTime {
            let timeDiff = lastProcessedTime - timestamp
            if timeDiff > timeToleranceNanos {
                logger.debug("[\(processID)] Skipping old/duplicate buffer: \(timestamp) vs \(lastProcessedTime)")
                return
            }
        }

        lastProcessedTime = timestamp

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let pcmBuffer = createPCMBuffer(from: sampleBuffer) else {
            return
        }

        // Wrap conversion in autoreleasepool to prevent memory buildup
        let result = autoreleasepool { () -> TranscriptionAudioBuffer? in
            do {
                // Use AudioConverter.resampleBuffer() -> [Float]
                let samples = try audioConverter.resampleBuffer(pcmBuffer)

                // Create 16kHz PCM buffer manually
                let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 16000,
                    channels: 1,
                    interleaved: false
                )!

                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: AVAudioFrameCount(samples.count)
                ) else { return nil }

                convertedBuffer.frameLength = AVAudioFrameCount(samples.count)
                guard let channelData = convertedBuffer.floatChannelData else { return nil }

                // Copy samples to buffer
                for (i, sample) in samples.enumerated() {
                    channelData[0][i] = sample
                }

                // Create transcription buffer
                let transcriptionBuffer = TranscriptionAudioBuffer(
                    buffer: convertedBuffer,
                    timestamp: timestamp,
                    source: .appAudio(processID: processID)
                )

                return transcriptionBuffer
            } catch {
                logger.error(
                    """
                    [\(processID)] Audio conversion failed:
                    Error: \(error)
                    Input format: \(pcmBuffer.format)
                    Frame length: \(pcmBuffer.frameLength)
                    Sample rate: \(pcmBuffer.format.sampleRate)
                    Channels: \(pcmBuffer.format.channelCount)
                    """
                )
                return nil
            }
        }

        if let transcriptionBuffer = result {
            await callback(transcriptionBuffer)
        }
    }

    // MARK: - CMSampleBuffer to AVAudioPCMBuffer Conversion

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Get audio format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }

        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = audioStreamBasicDescription else {
            return nil
        }

        // Create AVAudioFormat from description
        guard let format = AVAudioFormat(streamDescription: asbd) else {
            return nil
        }

        // Get frame count
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        // Create PCM buffer
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(numSamples)
        ) else {
            return nil
        }

        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Two-pass approach: Query required size first, then allocate and fill
        // Pass 1: Query the required buffer list size
        var requiredSize: Int = 0
        let queryStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )

        guard queryStatus == noErr, requiredSize > 0 else {
            return nil
        }

        // Pass 2: Allocate proper size and fill
        let channelCount = Int(format.channelCount)

        // Allocate the exact number of bytes CoreMedia told us we need
        let audioBufferListRawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        let audioBufferListPtr = audioBufferListRawPtr.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )
        let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)
        defer {
            audioBufferListRawPtr.deallocate()
        }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return nil
        }

        // Copy data to PCM buffer
        if let channelData = pcmBuffer.floatChannelData {
            for channel in 0..<min(audioBufferListPointer.count, channelCount) {
                let audioBuffer = audioBufferListPointer[channel]

                if let sourceData = audioBuffer.mData?.assumingMemoryBound(to: Float.self) {
                    channelData[channel].initialize(
                        from: sourceData,
                        count: Int(pcmBuffer.frameLength)
                    )
                }
            }
        }

        return pcmBuffer
    }
}
