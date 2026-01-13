import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: TranscriptionsStore
    @State private var editingSegmentID: UUID?
    @State private var editingSpeaker: Speaker?
    @StateObject private var audioPlayerViewModel = AudioMiniPlayerViewModel()
    @State private var resolvedAudioFileURL: URL?
    @State private var isAccessingSecurityScopedResource = false
    
    // UI State
    @State private var fontSize: Int = 12
    @State private var showTimestamps: Bool = false
    @State private var favoritesOnly: Bool = false
    @State private var groupSegmentsWithoutSpeakers: Bool = false
    @State private var speakerGroupingEnabled: Bool = false
    @State private var transcriptViewMode: TranscriptViewMode = .list
    @State private var searchText: String = ""
    @State private var newSpeakerName: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // Main transcript area
            VStack(spacing: 0) {
                // Top bar
                topBar
                
                // Transcript content
                ScrollView {
                    if let recording = store.selectedRecording {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredSegments(recording.segments)) { segment in
                                TranscriptSegmentView(
                                    segment: segment,
                                    fontSize: fontSize,
                                    showTimestamps: showTimestamps,
                                    isEditing: editingSegmentID == segment.id,
                                    onEdit: { editingSegmentID = segment.id },
                                    onSave: { newText in
                                        store.updateSegmentText(segment.id, newText: newText)
                                        editingSegmentID = nil
                                    },
                                    onCancel: { editingSegmentID = nil },
                                    onDelete: {
                                        store.deleteSegment(segment.id)
                                    },
                                    onEditSpeaker: {
                                        editingSpeaker = segment.speaker
                                    },
                                    onSeekToSegment: {
                                        if let recording = store.selectedRecording,
                                           let audioFileURL = resolvedAudioFileURL {
                                            audioPlayerViewModel.playFromSegment(
                                                startTime: segment.startTime,
                                                endTime: segment.endTime,
                                                segmentTimestamp: segment.timestamp,
                                                recordingStartDate: recording.startDate,
                                                segmentID: segment.id
                                            )
                                        }
                                    }
                                )
                            }
                        }
                        .padding(20)
                    }
                }
                
                // Playback controls at bottom
                if let recording = store.selectedRecording,
                   let audioFileURL = resolvedAudioFileURL {
                    playbackControls(recording: recording, audioFileURL: audioFileURL)
                }
            }
            
            // Right sidebar
            rightSidebar
        }
        .sheet(item: $editingSpeaker) { speaker in
            EditSpeakerSheet(
                speaker: speaker,
                onSave: { newName in
                    store.renameSpeaker(speaker, newName: newName)
                    editingSpeaker = nil
                },
                onCancel: { editingSpeaker = nil },
                onDelete: {
                    store.deleteSpeaker(speaker)
                    editingSpeaker = nil
                }
            )
        }
        .onChange(of: store.selectedRecording?.id) { oldValue, newValue in
            // Stop accessing previous resource
            if isAccessingSecurityScopedResource, let oldURL = resolvedAudioFileURL {
                oldURL.stopAccessingSecurityScopedResource()
                isAccessingSecurityScopedResource = false
            }
            resolvedAudioFileURL = nil
            
            // Resolve new URL if available
            if let recording = store.selectedRecording {
                resolvedAudioFileURL = resolveAudioFileURL(from: recording.audioFileURL)
            }
        }
        .onAppear {
            if let recording = store.selectedRecording {
                resolvedAudioFileURL = resolveAudioFileURL(from: recording.audioFileURL)
            }
        }
        .onDisappear {
            // Stop accessing security-scoped resource when view disappears
            if isAccessingSecurityScopedResource, let url = resolvedAudioFileURL {
                url.stopAccessingSecurityScopedResource()
                isAccessingSecurityScopedResource = false
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Spacer()
            
            Text(store.selectedRecording?.title ?? "")
                .font(.headline)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .help("Save")
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Upload")
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.plain)
                .help("Download")
                
                Menu {
                    Button("Export as Text") {}
                    Button("Export as PDF") {}
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                
                TextField("Search in transcript", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal")
                }
                .buttonStyle(.plain)
                .help("Settings")
                
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Add")
                
                Button(action: {}) {
                    Image(systemName: "photo")
                }
                .buttonStyle(.plain)
                .help("Image")
                
                Button(action: {}) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("Info")
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Share")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Playback Controls
    
    private func playbackControls(recording: RecordingViewModel, audioFileURL: URL) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                audioPlayerViewModel.togglePlayPause()
            }) {
                Image(systemName: audioPlayerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(audioPlayerViewModel.duration > 0 ? audioPlayerViewModel.currentTime / audioPlayerViewModel.duration : 0), height: 4)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = value.location.x / geometry.size.width
                            let newTime = TimeInterval(percentage) * audioPlayerViewModel.duration
                            audioPlayerViewModel.seek(to: newTime)
                        }
                )
            }
            .frame(height: 20)
            
            Text("1x")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            audioPlayerViewModel.loadAudio(url: audioFileURL, recordingStartDate: recording.startDate)
        }
    }
    
    // MARK: - Right Sidebar
    
    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Transcript View Options
            HStack(spacing: 12) {
                Button(action: { transcriptViewMode = .list }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16))
                        .foregroundColor(transcriptViewMode == .list ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: { transcriptViewMode = .grid }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 16))
                        .foregroundColor(transcriptViewMode == .grid ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            
            // Speaker Grouping
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speaker Grouping")
                        .font(.headline)
                    Text("BETA")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                
                Toggle("", isOn: $speakerGroupingEnabled)
                    .toggleStyle(.switch)
            }
            
            Divider()
            
            // Speakers List
            VStack(alignment: .leading, spacing: 12) {
                Text("Speakers")
                    .font(.headline)
                
                if let recording = store.selectedRecording {
                    let speakers = getUniqueSpeakers(from: recording.segments)
                    ForEach(Array(speakers.enumerated()), id: \.element.id) { index, speaker in
                        HStack {
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            
                            Text(speaker.displayName)
                                .font(.subheadline)
                                .foregroundColor(colorForSpeaker(speaker))
                        }
                    }
                    
                    TextField("Add a speaker...", text: $newSpeakerName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            // TODO: Add speaker creation
                            newSpeakerName = ""
                        }
                }
            }
            
            Divider()
            
            // Options
            VStack(alignment: .leading, spacing: 16) {
                Text("Options")
                    .font(.headline)
                
                // Font Size
                HStack {
                    Text("Font Size")
                    Spacer()
                    Menu {
                        ForEach([12, 14, 16, 18, 20, 22, 24], id: \.self) { size in
                            Button("\(size)") {
                                fontSize = size
                            }
                        }
                    } label: {
                        HStack {
                            Text("\(fontSize)")
                        }
                    }
                }
                
                // Show Timestamps
                HStack {
                    Text("Show Timestamps")
                    Spacer()
                    Toggle("", isOn: $showTimestamps)
                        .toggleStyle(.switch)
                }
                
                // Favorites Only
                HStack {
                    Text("Favorites Only")
                    Spacer()
                    Toggle("", isOn: $favoritesOnly)
                        .toggleStyle(.switch)
                }
                
                // Group Segments Without Speakers
                HStack {
                    Text("Group Segments Without Speakers")
                    Spacer()
                    Toggle("", isOn: $groupSegmentsWithoutSpeakers)
                        .toggleStyle(.switch)
                }
                
                Button("Adjust Start Timestamp") {
                    // TODO: Implement timestamp adjustment
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Helper Functions
    
    private func filteredSegments(_ segments: [TranscriptionSegmentViewModel]) -> [TranscriptionSegmentViewModel] {
        var filtered = segments
        
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
        
        if favoritesOnly {
            // TODO: Implement favorites filtering
        }
        
        if groupSegmentsWithoutSpeakers {
            // TODO: Implement grouping
        }
        
        return filtered
    }
    
    private func getUniqueSpeakers(from segments: [TranscriptionSegmentViewModel]) -> [Speaker] {
        var speakers: [Speaker] = []
        var seenIDs: Set<UUID> = []
        
        for segment in segments {
            if let speaker = segment.speaker, !seenIDs.contains(speaker.id) {
                speakers.append(speaker)
                seenIDs.insert(speaker.id)
            }
        }
        
        return speakers.sorted { $0.displayName < $1.displayName }
    }
    
    private func colorForSpeaker(_ speaker: Speaker) -> Color {
        let colors: [Color] = [.red, .blue, .green, .purple, .orange, .pink, .cyan, .mint, .indigo, .yellow]
        let index = abs(speaker.id.hashValue) % colors.count
        return colors[index]
    }
    
    // Helper function to resolve URL from bookmark string
    private func resolveAudioFileURL(from bookmarkString: String?) -> URL? {
        guard let bookmarkString = bookmarkString,
              let bookmarkData = Data(base64Encoded: bookmarkString) else {
            return nil
        }
        
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        
        isAccessingSecurityScopedResource = true
        return url
    }
}

enum TranscriptViewMode {
    case list
    case grid
}

// MARK: - Transcript Segment View

struct TranscriptSegmentView: View {
    let segment: TranscriptionSegmentViewModel
    let fontSize: Int
    let showTimestamps: Bool
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: (String) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onEditSpeaker: () -> Void
    let onSeekToSegment: () -> Void
    
    @State private var editedText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let speaker = segment.speaker {
                Button(action: onEditSpeaker) {
                    Text(speaker.displayName)
                        .font(.system(size: CGFloat(fontSize), weight: .semibold))
                        .foregroundColor(colorForSpeaker(speaker))
                }
                .buttonStyle(.plain)
            } else {
                Text("No Speaker")
                    .font(.system(size: CGFloat(fontSize), weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            if showTimestamps {
                Text(segment.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isEditing {
                TextEditor(text: $editedText)
                    .font(.system(size: CGFloat(fontSize)))
                    .frame(minHeight: 60)
                    .focused($isFocused)
                    .onAppear {
                        editedText = segment.text
                        isFocused = true
                    }
                
                HStack {
                    Button("Save") {
                        onSave(editedText)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Button(action: onSeekToSegment) {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Play from segment start")
                    
                    Text(segment.text)
                        .font(.system(size: CGFloat(fontSize)))
                        .textSelection(.enabled)
                }
                .contextMenu {
                    Button {
                        onSeekToSegment()
                    } label: {
                        Label("Play from here", systemImage: "play")
                    }
                    
                    Button {
                        editedText = segment.text
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func colorForSpeaker(_ speaker: Speaker) -> Color {
        let colors: [Color] = [.red, .blue, .green, .purple, .orange, .pink, .cyan, .mint, .indigo, .yellow]
        let index = abs(speaker.id.hashValue) % colors.count
        return colors[index]
    }
}
