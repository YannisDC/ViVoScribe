import SwiftUI
import AppKit

struct EditSpeakerSheet: View {
    let speaker: Speaker
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var newName: String
    @State private var selectedColor: Color
    @State private var showDeleteConfirmation = false
    @FocusState private var isNameFieldFocused: Bool
    
    // Predefined color palette
    private let colorPalette: [Color] = [
        .red, .blue, .green, .orange, .purple, .pink, 
        .cyan, .mint, .indigo, .yellow, .teal, .brown
    ]

    init(speaker: Speaker, onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.speaker = speaker
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _newName = State(initialValue: speaker.customName ?? "")
        
        // Initialize color from stored hex or use default
        if let hex = speaker.colorHex, let color = Color(hex: hex) {
            _selectedColor = State(initialValue: color)
        } else {
            // Use hash-based color as default
            let colors: [Color] = [.red, .blue, .green, .purple, .orange, .pink, .cyan, .mint, .indigo, .yellow]
            let index = abs(speaker.id.hashValue) % colors.count
            _selectedColor = State(initialValue: colors[index])
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Speaker")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Name section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Current: \(speaker.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Speaker name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFieldFocused)
                        .onSubmit { save() }

                    Text("Leave blank to use default name")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Color section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Color palette grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(colorPalette, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                                    )
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
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

                Button("Save") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360)
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
    
    private func save() {
        let colorHex = selectedColor.toHex()
        onSave(newName, colorHex)
    }
}

// MARK: - Color Extension for Hex Conversion

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        let nsColor = NSColor(self)
        
        guard let components = nsColor.cgColor.components, components.count >= 3 else {
            return "000000"
        }
        
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
