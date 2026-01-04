import Foundation
import OSLog
import AVFoundation
import Combine
import ScreenCaptureKit

@MainActor
final class AudioManager: ObservableObject {
    private let logger = Logging(name: "AudioManager")

    // Core components
    private let audioInput = AudioInput()
    private let applicationAudio = ApplicationAudio()
    private let transcriber = Transcriber()
    private let audioMonitor = AudioMonitor()

    // State
    @Published private(set) var isRecording = false
    @Published private(set) var microphoneActive = false
    @Published private(set) var appAudioActive = false
    @Published private(set) var isMuted = false

    // Callback for transcription results
    var onTranscriptionResult: (@Sendable (TranscriptionResult) -> Void)?

    init() {
        // Always monitor for audio processes
        audioMonitor.startMonitoring()

        // Set up callbacks (but only create streams when recording)
        audioMonitor.onProcessStarted = { [weak self] process in
            await self?.handleProcessStarted(process: process)
        }

        audioMonitor.onProcessStopped = { [weak self] processID in
            await self?.handleProcessStopped(processID: processID)
        }
    }

    // MARK: - Recording Control

    func startRecording(microphoneDeviceID: AudioDeviceID, appProcessID: pid_t) async throws {
        guard !isRecording else { return }

        // Debug: Log permission state and app identity
        let bid = Bundle.main.bundleIdentifier ?? "nil"
        let exe = CommandLine.arguments.first ?? "nil"
        logger.info("preflight=\(CGPreflightScreenCaptureAccess()) bid=\(bid) exe=\(exe)")

        // Guard: Check microphone permission first
        guard checkMicrophonePermission() else {
            logger.error("❌ Microphone permission not granted")
            throw AudioManagerError.permissionDenied
        }

        // Guard: Check screen recording permission (without triggering prompt)
        if !checkScreenRecordingPermission() {
            logger.info("⚠️ Screen recording permission not granted - requesting...")
            requestScreenRecordingPermission()
            throw AudioManagerError.permissionDenied
        }

        logger.info("Starting recording - mic device: \(microphoneDeviceID)")

        // Initialize transcriber
        try await transcriber.initialize()

        // Start transcriber
        try await transcriber.startTranscription { [weak self] result in
            // Handle transcription results with diarization
            let speaker = result.speakerLabel ?? "Unknown"
            let sourceIcon = switch result.audioSource {
            case .microphone: "🎤"
            case .appAudio: "🔊"
            }
            print("💬 \(sourceIcon) [\(speaker)] \(result.text)")

            // Forward to UI callback - dispatch to main actor
            Task { @MainActor [weak self] in
                self?.onTranscriptionResult?(result)
            }
        }

        // Set recording flag FIRST so that stream creation works for already-detected processes
        isRecording = true

        do {
            // Start microphone input
            try await startMicrophone(deviceID: microphoneDeviceID)

            // Start app audio capture (will create streams for detected processes)
            try await startAppAudio()

            logger.info("✅ Recording started successfully")
        } catch {
            // Reset recording flag if startup failed
            isRecording = false
            throw error
        }
    }

    func stopRecording() async throws {
        guard isRecording else { return }

        logger.info("Stopping recording")

        // Stop transcriber
        try? await transcriber.stopTranscription()

        // Stop audio sources (this cleans up all streams)
        await audioInput.stopRecording()
        await applicationAudio.deactivate()

        isRecording = false
        microphoneActive = false
        appAudioActive = false

        // Monitoring continues running for auto-record features
        logger.info("Recording stopped (monitoring continues)")
    }

    // MARK: - Private Methods

    private func startMicrophone(deviceID: AudioDeviceID) async throws {
        await audioInput.configure(deviceID: deviceID)

        try await audioInput.startRecording { [weak self] buffer in
            Task { [weak self] in
                guard let self = self else { return }

                // Send full TranscriptionAudioBuffer to transcriber (includes source info)
                do {
                    try await self.transcriber.processAudioChunk(buffer)
                } catch {
                    self.logger.error("Audio processing failed: \(error)")
                }
            }
        }

        microphoneActive = true
        logger.info("Microphone active")
    }

    private func startAppAudio() async throws {
        try await applicationAudio.activate()

        try await applicationAudio.startCapture { [weak self] buffer in
            Task { [weak self] in
                guard let self = self else { return }

                // Send full TranscriptionAudioBuffer to transcriber (includes source info)
                do {
                    try await self.transcriber.processAudioChunk(buffer)
                } catch {
                    self.logger.error("App audio processing failed: \(error)")
                }
            }
        }

        appAudioActive = true
        logger.info("App audio capture activated")

        // Start monitoring active processes and create streams
        await startProcessMonitoring()
    }

    private func startProcessMonitoring() async {
        // Wait briefly for monitoring to detect processes
        try? await Task.sleep(for: .milliseconds(500))

        // Get initial active audio processes and create streams for them
        let processes = getActiveAudioProcesses()

        logger.info("Found \(processes.count) active audio processes - creating initial streams")

        for process in processes {
            await handleProcessStarted(process: process)
        }
    }

    private func handleProcessStarted(process: AudioProcess) async {
        logger.info("Process started: \(process.name) (PID: \(process.id))")

        // Only create streams if we're currently recording
        guard isRecording else {
            logger.info("Not recording - skipping stream creation for \(process.name)")
            return
        }

        // Pass process to ApplicationAudio - it handles everything
        do {
            try await applicationAudio.handleProcessStarted(process: process)
            logger.info("✅ Stream creation completed for \(process.name)")
        } catch {
            logger.error("Failed to create stream for \(process.name): \(error)")
        }
    }

    private func handleProcessStopped(processID: pid_t) async {
        logger.info("Handling process stopped: PID \(processID)")
        await applicationAudio.handleProcessStopped(processID: processID)
    }

    // MARK: - Public Interface

    func getActiveAudioProcesses() -> [AudioProcess] {
        audioMonitor.getActiveAudioProcesses()
    }

    var hasActiveAudio: Bool {
        audioMonitor.hasActiveAudio
    }

    func checkMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }

    func checkScreenRecordingPermission() -> Bool {
        // Check permission without triggering prompt
        let hasPermission = CGPreflightScreenCaptureAccess()
        if hasPermission {
            logger.info("✅ Screen recording permission granted")
        } else {
            logger.info("⚠️ Screen recording permission not granted")
        }
        return hasPermission
    }

    func requestScreenRecordingPermission() {
        // Trigger the permission prompt by requesting access
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Mute Control
    func setMuted(_ muted: Bool) async {
        await audioInput.setMuted(muted)
        isMuted = muted
    }

    func toggleMute() async {
        await audioInput.toggleMute()
        isMuted = await audioInput.isMicrophoneMuted()
    }

    func getMuteState() async -> Bool {
        return await audioInput.isMicrophoneMuted()
    }
}

enum AudioManagerError: Error {
    case permissionDenied
    case microphoneFailed
    case appAudioFailed
    case transcriberFailed
}