import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Bindable var store: TranscriptionsStore
    @State private var showFileImporter = false
    @State private var urlInput = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Top Bar
                topBar
                
                // Action Buttons Grid
                actionButtonsGrid
                
                // Transcriptions Section
                transcriptionsSection
                
                // Meetings Section
                meetingsSection
            }
            .padding(20)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie, .video],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    await importAudioFile(url: url)
                }
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        VStack(spacing: 12) {
            // URL Input
            HStack(spacing: 12) {
                TextField("Enter YouTube, Audio or Video File URL...", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                
                // Model and Language dropdowns
                Menu {
                    Button("English") {}
                } label: {
                    HStack {
                        Image(systemName: "applelogo")
                            .font(.system(size: 12))
                        Text("Model English")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                }
                
                Menu {
                    Button("English") {}
                } label: {
                    Text("Language English")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                }
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Q", text: .constant(""))
                        .textFieldStyle(.plain)
                        .frame(width: 100)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Action Buttons Grid
    
    private var actionButtonsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            ActionButton(
                icon: "mic.fill",
                title: "New Voice Memo",
                action: { /* Start voice memo */ }
            )
            
            ActionButton(
                icon: "folder.badge.plus",
                title: "Open Files",
                action: { showFileImporter = true }
            )
            
            ActionButton(
                icon: "record.circle",
                title: "Record App Audio",
                action: { /* Record app audio */ }
            )
            
            ActionButton(
                icon: "person.2.fill",
                title: "Podcasts",
                action: { /* Open podcasts */ }
            )
            
            ActionButton(
                icon: "square.and.arrow.up",
                title: "Batch Export",
                action: { /* Batch export */ }
            )
            
            ActionButton(
                icon: "square.stack.3d.up.fill",
                title: "Manage Models",
                action: { /* Manage models */ }
            )
            
            ActionButton(
                icon: "video.fill",
                title: "Record Zoom",
                action: { /* Record Zoom */ }
            )
            
            ActionButton(
                icon: "video.fill",
                title: "Record Webex",
                action: { /* Record Webex */ }
            )
        }
    }
    
    // MARK: - Transcriptions Section
    
    private var transcriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcriptions")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(">") {
                    // Navigate to transcriptions list
                    store.clearSelectedRecording()
                }
                .buttonStyle(.plain)
            }
            
            if store.recordings.isEmpty {
                Text("No transcriptions yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(store.recordings.prefix(10)) { recording in
                            TranscriptionCard(recording: recording, store: store)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    // MARK: - Meetings Section
    
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Meetings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(">") {
                    // Navigate to transcriptions list (meetings are also transcriptions)
                    store.clearSelectedRecording()
                }
                .buttonStyle(.plain)
            }
            
            let meetings = store.recordings.filter { $0.segmentCount > 0 }
            if meetings.isEmpty {
                Text("No meetings yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(meetings.prefix(10)) { recording in
                            MeetingCard(recording: recording, store: store)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func importAudioFile(url: URL) async {
        do {
            try await store.importAudioFile(url: url)
        } catch {
            print("Failed to import audio file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transcription Card

struct TranscriptionCard: View {
    let recording: RecordingViewModel
    @Bindable var store: TranscriptionsStore
    @State private var loadedRecording: RecordingViewModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(formatDuration(recording.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let loaded = loadedRecording, let firstSegment = loaded.segments.first {
                    Text(firstSegment.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if recording.segmentCount > 0 {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text("No transcription available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0), lineWidth: 2)
        )
        .onTapGesture {
            store.setSelectedRecording(recording.id)
        }
        .onAppear {
            if recording.segments.isEmpty && recording.segmentCount > 0 {
                loadRecordingWithSegments()
            } else {
                loadedRecording = recording
            }
        }
        .help("Click to view full transcript")
    }
    
    private func loadRecordingWithSegments() {
        store.setSelectedRecording(recording.id)
        // After a brief delay, get the loaded recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let selected = store.selectedRecording, selected.id == recording.id {
                loadedRecording = selected
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Meeting Card

struct MeetingCard: View {
    let recording: RecordingViewModel
    @Bindable var store: TranscriptionsStore
    @State private var loadedRecording: RecordingViewModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(formatDuration(recording.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let loaded = loadedRecording, let firstSegment = loaded.segments.first {
                    Text(firstSegment.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if recording.segmentCount > 0 {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text("No transcription available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0), lineWidth: 2)
        )
        .onTapGesture {
            store.setSelectedRecording(recording.id)
        }
        .onAppear {
            if recording.segments.isEmpty && recording.segmentCount > 0 {
                loadRecordingWithSegments()
            } else {
                loadedRecording = recording
            }
        }
        .help("Click to view full transcript")
    }
    
    private func loadRecordingWithSegments() {
        store.setSelectedRecording(recording.id)
        // After a brief delay, get the loaded recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let selected = store.selectedRecording, selected.id == recording.id {
                loadedRecording = selected
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
