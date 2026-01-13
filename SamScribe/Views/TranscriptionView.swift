import SwiftUI
import SwiftData
import CoreAudio
import AVFoundation
import CoreGraphics

struct TranscriptionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store = TranscriptionsStore()
    @StateObject private var audioManager = AudioManager()

    // Permission states
    @State private var microphonePermission: PermissionState = .checking
    @State private var screenRecordingPermission: PermissionState = .checking
    @State private var showMicrophoneAlert = false
    @State private var showScreenRecordingAlert = false
    
    // File import
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var importError: String?

    @State private var selectedSection: SidebarSection = .home
    
    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selectedSection: $selectedSection)
        } detail: {
            if let recording = store.selectedRecording {
                RecordingDetailView(store: store)
                    .navigationTitle(recording.title)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button {
                                store.clearSelectedRecording()
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                            }
                        }
                    }
            } else {
                switch selectedSection {
                case .transcriptions:
                    TranscriptionsListView(store: store)
                case .home:
                    HomeView(store: store)
                        .navigationTitle("Home")
                default:
                    HomeView(store: store)
                        .navigationTitle("Home")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    Button {
                        importAudioFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Audio")
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.currentRecording != nil || isImporting)
                    
                    Button {
                        if store.currentRecording != nil {
                            stopRecording()
                        } else {
                            checkPermissionsAndStartRecording()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: store.currentRecording != nil ? "stop.circle.fill" : "waveform")
                            Text(store.currentRecording != nil ? "Stop Transcribing" : "Start Transcribing")
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.currentRecording != nil ? .red : .accentColor)
                    .disabled(microphonePermission == .checking || screenRecordingPermission == .checking)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await importAudioFile(url: url)
                    }
                }
            case .failure(let error):
                print("File import failed: \(error.localizedDescription)")
            }
        }
        .alert("Microphone Permission Required", isPresented: $showMicrophoneAlert) {
            Button("Open Settings") {
                openSystemPreferences(for: .microphone)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SamScribe needs microphone access to transcribe audio. Please grant permission in System Settings > Privacy & Security > Microphone.")
        }
        .alert("Screen Recording Permission Required", isPresented: $showScreenRecordingAlert) {
            Button("Open Settings") {
                openSystemPreferences(for: .screenRecording)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SamScribe needs screen recording permission to capture app audio. Please grant permission in System Settings > Privacy & Security > Screen Recording.")
        }
        .onAppear {
            store.initialize(with: modelContext)
            setupTranscriptionCallback()
            Task {
                await checkPermissionsOnLaunch()
            }
        }
    }

    // MARK: - Recording Management

    private func startRecording() {
        store.createNewRecording()

        Task {
            do {
                // Get default audio input device
                let microphoneDeviceID = try AudioDeviceID.readDefaultSystemInputDevice()

                // Use process ID 0 (system processes) or find a meeting app
                let appProcessID: pid_t = 0

                try await audioManager.startRecording(
                    microphoneDeviceID: microphoneDeviceID,
                    appProcessID: appProcessID
                )
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    private func stopRecording() {
        store.stopCurrentRecording()

        Task {
            do {
                try await audioManager.stopRecording()
            } catch {
                print("Failed to stop recording: \(error)")
            }
        }
    }

    // MARK: - Transcription Integration

    private func setupTranscriptionCallback() {
        audioManager.onTranscriptionResult = { [store] result in
            Task { @MainActor in
                store.addTranscriptionSegment(result)
            }
        }
    }

    // MARK: - Permission Management

    private func checkPermissionsOnLaunch() async {
        await checkMicrophonePermission()
        await checkScreenRecordingPermission()
    }

    private func checkMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        await MainActor.run {
            switch status {
            case .authorized:
                microphonePermission = .granted
            case .notDetermined:
                microphonePermission = .notDetermined
                Task {
                    await requestMicrophonePermission()
                }
            case .denied, .restricted:
                microphonePermission = .denied
            @unknown default:
                microphonePermission = .denied
            }
        }
    }

    private func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)

        await MainActor.run {
            microphonePermission = granted ? .granted : .denied
        }
    }

    private func checkScreenRecordingPermission() async {
        let hasPermission = CGPreflightScreenCaptureAccess()

        await MainActor.run {
            screenRecordingPermission = hasPermission ? .granted : .notDetermined
        }
    }

    private func requestScreenRecordingPermission() {
        // Request screen recording permission
        // This will trigger a system prompt if not already determined
        let _ = CGRequestScreenCaptureAccess()

        // Re-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                await checkScreenRecordingPermission()
            }
        }
    }

    private func checkPermissionsAndStartRecording() {
        // Check if microphone permission is granted
        if microphonePermission == .notDetermined {
            Task {
                await requestMicrophonePermission()
                checkPermissionsAndStartRecording() // Retry after request
            }
            return
        } else if microphonePermission == .denied {
            showMicrophoneAlert = true
            return
        }

        // Check if screen recording permission is granted
        if screenRecordingPermission == .notDetermined {
            requestScreenRecordingPermission()

            // Show alert to guide user
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showScreenRecordingAlert = true
            }
            return
        } else if screenRecordingPermission == .denied {
            showScreenRecordingAlert = true
            return
        }

        // Both permissions granted, start recording
        startRecording()
    }

    private func openSystemPreferences(for type: PermissionType) {
        let urlString: String
        switch type {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Audio File Import
    
    private func importAudioFile() {
        showFileImporter = true
    }
    
    private func importAudioFile(url: URL) async {
        isImporting = true
        importError = nil
        
        defer {
            isImporting = false
        }
        
        do {
            try await store.importAudioFile(url: url)
        } catch {
            importError = error.localizedDescription
            print("Failed to import audio file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Permission Types

enum PermissionState: Equatable {
    case checking
    case granted
    case denied
    case notDetermined
}

enum PermissionType {
    case microphone
    case screenRecording
}
