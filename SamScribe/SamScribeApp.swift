import SwiftUI
import SwiftData
import AVFoundation

@main
struct SamScribeApp: App {
    // Add ModelContainer
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            TranscriptionSegment.self,
            Speaker.self  // NEW: Add Speaker model
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TranscriptionView()
        }
        .modelContainer(sharedModelContainer)
    }
}

enum PermissionStatus {
    case checking
    case granted
    case denied
    case notDetermined

    var buttonText: String {
        switch self {
        case .checking: return "Checking Permission..."
        case .granted: return "Start Recording"
        case .denied, .notDetermined: return "Grant Microphone Permission"
        }
    }

    var isRecordingAllowed: Bool {
        return self == .granted
    }
}

struct RootView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var transcripts: [TranscriptionResult] = []
    @State private var isRecording = false
    @State private var isInitializing = false
    @State private var currentTranscript = ""
    @State private var errorMessage: String?
    @State private var permissionStatus: PermissionStatus = .checking
    @State private var showPermissionAlert = false
    @State private var isMuted = false

    private var buttonBackground: Color {
        if permissionStatus == .checking || isInitializing {
            return Color.gray
        }
        if permissionStatus == .denied {
            return Color.orange
        }
        return isRecording ? Color.red : Color.blue
    }

    private var canInteractWithButton: Bool {
        return permissionStatus != .checking && !isInitializing
    }

    private var buttonText: String {
        if isInitializing {
            return "Starting Recording..."
        }
        if isRecording {
            return "Stop Recording"
        }
        return permissionStatus.buttonText
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Transcription App")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

            // Status
            HStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)

                Text(isRecording ? "Recording..." : "Stopped")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Permission status message
            if permissionStatus == .denied {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Microphone permission denied. Please enable in System Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            } else if permissionStatus == .notDetermined {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Microphone permission required to start recording.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            // Main Action Buttons
            HStack(spacing: 12) {
                // Recording Button
                Button(action: {
                    Task {
                        if isRecording {
                            await stopRecording()
                        } else {
                            if permissionStatus == .granted {
                                await startRecording()
                            } else if permissionStatus == .notDetermined {
                                await requestMicrophonePermission()
                            } else {
                                showPermissionAlert = true
                            }
                        }
                    }
                }) {
                    HStack {
                        if isInitializing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(buttonText)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonBackground)
                    .cornerRadius(10)
                }
                .disabled(!canInteractWithButton)

                // Mute Button
                Button(action: {
                    Task {
                        await toggleMute()
                    }
                }) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(isMuted ? Color.orange : Color.blue)
                        .cornerRadius(10)
                }
                .disabled(!isRecording)
            }
            .padding(.horizontal)
            .alert("Microphone Permission Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable microphone access in System Settings to use this app.")
            }

            // Error Message
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // Live Transcript
            if !currentTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Transcript:")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(currentTranscript)
                        .font(.body)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
            }

            // Transcript History
            if !transcripts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previous Transcripts:")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(transcripts.enumerated().reversed()), id: \.offset) { index, transcript in
                                TranscriptRow(transcript: transcript)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else if isRecording {
                Text("Waiting for transcripts...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }

            Spacer()
        }
        .padding()
        .onAppear {
            Task {
                await checkMicrophonePermissionOnLaunch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await checkMicrophonePermissionOnLaunch()
            }
        }
    }

    private func startRecording() async {
        isInitializing = true
        defer { isInitializing = false }

        do {
            errorMessage = nil

            // Get default audio input device
            let microphoneDeviceID = try AudioDeviceID.readDefaultSystemInputDevice()

            // For testing, use process ID 0 (system processes) or find a meeting app
            // In a real implementation, you'd have UI to select the target app
            let appProcessID: pid_t = 0

            try await audioManager.startRecording(
                microphoneDeviceID: microphoneDeviceID,
                appProcessID: appProcessID
            )

            // Set up transcription result handler
            audioManager.onTranscriptionResult = { result in
                DispatchQueue.main.async {
                    // Add to history
                    transcripts.append(result)

                    // Sort by timestamp to ensure chronological order across all sources
                    transcripts.sort { $0.timestamp < $1.timestamp }

                    // Update live transcript
                    let speaker = result.speakerLabel ?? "Unknown"
                    let source = result.audioSource == .microphone ? "🎤" : "🔊"
                    currentTranscript = "\(source) [\(speaker)] \(result.text)"

                    // Keep only last 50 transcripts to avoid memory issues
                    if transcripts.count > 50 {
                        transcripts.removeFirst()
                    }
                }
            }

            isRecording = true
            isMuted = await audioManager.getMuteState()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        do {
            try await audioManager.stopRecording()
            isRecording = false
            isMuted = false
            currentTranscript = ""
            errorMessage = nil
        } catch {
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
        }
    }

    private func toggleMute() async {
        await audioManager.toggleMute()
        isMuted = await audioManager.getMuteState()
    }

    private func checkMicrophonePermissionOnLaunch() async {
        permissionStatus = .checking

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        await MainActor.run {
            switch status {
            case .authorized:
                permissionStatus = .granted
            case .notDetermined:
                permissionStatus = .notDetermined
            case .denied, .restricted:
                permissionStatus = .denied
            @unknown default:
                permissionStatus = .denied
            }
        }
    }

    private func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)

        await MainActor.run {
            if granted {
                permissionStatus = .granted
            } else {
                permissionStatus = .denied
                showPermissionAlert = true
            }
        }
    }
}

struct TranscriptRow: View {
    let transcript: TranscriptionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with source, speaker, and time
            HStack {
                Text(sourceIcon)
                    .font(.caption)

                Text(transcript.speakerLabel ?? "Unknown Speaker")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(transcript.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if transcript.confidence > 0 {
                    Text("\(Int(transcript.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Transcript text
            Text(transcript.text)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var sourceIcon: String {
        switch transcript.audioSource {
        case .microphone:
            return "🎤"
        case .appAudio:
            return "🔊"
        case .fileAudio:
            return "📁"
        }
    }
}

#Preview {
    RootView()
}
