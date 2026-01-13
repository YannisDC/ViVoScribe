import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: TranscriptionsStore
    @State private var editingSegmentID: UUID?
    @State private var editingSpeaker: Speaker?
    @StateObject private var audioPlayerViewModel = AudioMiniPlayerViewModel()
    @State private var resolvedAudioFileURL: URL?
    @State private var isAccessingSecurityScopedResource = false

    var body: some View {
        VStack(spacing: 0) {
            // Transcript on top
            ScrollView {
                if let recording = store.selectedRecording {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(recording.segments) { segment in
                            TranscriptSegmentRow(
                                segment: segment,
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
            
            // Miniplayer at the bottom, full width
            if let recording = store.selectedRecording,
               let audioFileURL = resolvedAudioFileURL {
                AudioMiniPlayer(
                    viewModel: audioPlayerViewModel,
                    audioFileURL: audioFileURL,
                    recordingStartDate: recording.startDate
                )
            }
        }
        .sheet(item: $editingSpeaker) { speaker in
            EditSpeakerSheet(
                speaker: speaker,
                onSave: { newName in
                    store.renameSpeaker(speaker, newName: newName)
                    editingSpeaker = nil
                },
                onCancel: { editingSpeaker = nil }
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
