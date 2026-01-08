import SwiftUI

struct EditSpeakerSheet: View {
    let speaker: Speaker
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var newName: String
    @FocusState private var isNameFieldFocused: Bool

    init(speaker: Speaker, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.speaker = speaker
        self.onSave = onSave
        self.onCancel = onCancel
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
            }

            HStack(spacing: 12) {
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
    }
}
