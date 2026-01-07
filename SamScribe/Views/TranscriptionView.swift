import SwiftUI
import SwiftData
import CoreAudio

struct TranscriptionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store = TranscriptionsStore()
    @StateObject private var audioManager = AudioManager()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            if let recording = store.selectedRecording {
                RecordingDetailView(store: store)
                    .navigationTitle(recording.title)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text(store.recordings.isEmpty ? "Start a recording" : "Select a recording")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .navigationTitle("SamScribe")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    if store.currentRecording != nil {
                        stopRecording()
                    } else {
                        startRecording()
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
            }
        }
        .onAppear {
            store.initialize(with: modelContext)
            setupTranscriptionCallback()
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
}
