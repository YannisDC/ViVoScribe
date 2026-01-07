import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: TranscriptionsStore
    @State private var editingSegmentID: UUID?

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
                            }
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}
