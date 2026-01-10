import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: TranscriptionsStore
    @State private var editingSegmentID: UUID?
    @State private var editingSpeaker: Speaker?

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
                            }
                        )
                    }
                }
                .padding(20)
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
    }
}
