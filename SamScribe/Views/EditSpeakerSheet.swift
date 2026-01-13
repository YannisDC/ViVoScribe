import SwiftUI

struct EditSpeakerSheet: View {
    let speaker: Speaker
    let onSave: (String) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var newName: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isNameFieldFocused: Bool

    init(speaker: Speaker, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.speaker = speaker
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _newName = State(initialValue: speaker.customName ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Speaker Name")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Current: \(speaker.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Speaker name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .onSubmit { onSave(newName) }

                Text("Leave blank to use default name")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if speaker.segments.count > 0 {
                    Text("This speaker has \(speaker.segments.count) segment\(speaker.segments.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 12) {
                if let onDelete = onDelete {
                    Button("Delete") {
                        showDeleteConfirmation = true
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Spacer()
                
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)

                Button("Save") { onSave(newName) }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { isNameFieldFocused = true }
        .alert("Delete Speaker", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(speaker.displayName)\"? This will remove the speaker from all associated segments.")
        }
    }
}
