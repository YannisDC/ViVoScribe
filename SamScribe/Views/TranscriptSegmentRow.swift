import SwiftUI

struct TranscriptSegmentRow: View {
    let segment: TranscriptionSegmentViewModel
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: (String) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onEditSpeaker: () -> Void
    let onSeekToSegment: () -> Void

    @State private var editedText: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Metadata
                HStack(spacing: 8) {
                    // Speaker avatar
                    SpeakerAvatarView(speaker: segment.speaker, size: 24)
                    
                    if let speakerLabel = segment.speakerLabel {
                        // Has speaker - show with edit button
                        Button(action: onEditSpeaker) {
                            HStack(spacing: 6) {
                                Text(speakerLabel)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)

                                Image(systemName: "pencil")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        // No speaker - just show label without edit button
                        Text("No Speaker")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }

                    Text(segment.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Seek to segment button
                    Button(action: onSeekToSegment) {
                        Image(systemName: "play.circle")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Play from segment start")
                }

                // Transcript text (editable)
                if isEditing {
                    TextEditor(text: $editedText)
                        .font(.body)
                        .frame(minHeight: 60)
                        .border(Color.accentColor, width: 1)

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
                    Text(segment.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            // Actions
            if !isEditing {
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
