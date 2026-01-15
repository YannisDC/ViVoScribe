import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditSpeakerSheet: View {
    let speaker: Speaker
    let onSave: (String, String?, Data?) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var newName: String
    @State private var selectedColor: Color
    @State private var selectedImageData: Data?
    @State private var showDeleteConfirmation = false
    @State private var showImagePicker = false
    @FocusState private var isNameFieldFocused: Bool
    
    // Predefined color palette
    private let colorPalette: [Color] = [
        .red, .blue, .green, .orange, .purple, .pink, 
        .cyan, .mint, .indigo, .yellow, .teal, .brown
    ]

    init(speaker: Speaker, onSave: @escaping (String, String?, Data?) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.speaker = speaker
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _newName = State(initialValue: speaker.customName ?? "")
        _selectedImageData = State(initialValue: speaker.imageData)
        
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
                
                // Image section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        // Display current image or placeholder
                        if let imageData = selectedImageData, let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Choose Image...") {
                                showImagePicker = true
                            }
                            .buttonStyle(.bordered)
                            
                            if selectedImageData != nil {
                                Button("Remove Image") {
                                    selectedImageData = nil
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                    }
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
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                // Load image data
                if let imageData = try? Data(contentsOf: url) {
                    // Resize image to reasonable size (max 512x512) to save storage
                    if let nsImage = NSImage(data: imageData) {
                        let resizedImage = resizeImage(nsImage, maxDimension: 512)
                        // Convert to PNG for better compression
                        if let resized = resizedImage,
                           let tiffData = resized.tiffRepresentation,
                           let bitmapRep = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                            selectedImageData = pngData
                        } else {
                            selectedImageData = imageData
                        }
                    } else {
                        selectedImageData = imageData
                    }
                }
            }
        }
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
        onSave(newName, colorHex, selectedImageData)
    }
    
    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        let aspectRatio = size.width / size.height
        var newSize: NSSize
        
        if size.width > size.height {
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .sourceOver,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        
        return resizedImage
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
