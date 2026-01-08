import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: TranscriptionsStore
    @State private var editingSegmentID: UUID?
    @State private var editingSpeaker: Speaker?
    @State private var showSpeakerSheet = false

    var body: some View {
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
                                showSpeakerSheet = true
                            }
                        )
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showSpeakerSheet) {
            if let speaker = editingSpeaker {
                EditSpeakerSheet(
                    speaker: speaker,
                    onSave: { newName in
                        store.renameSpeaker(speaker, newName: newName)
                        showSpeakerSheet = false
                    },
                    onCancel: { showSpeakerSheet = false }
                )
            }
        }
    }
}
