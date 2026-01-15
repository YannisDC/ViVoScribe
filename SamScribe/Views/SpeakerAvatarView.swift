import SwiftUI
import AppKit

struct SpeakerAvatarView: View {
    let speaker: Speaker?
    let size: CGFloat
    let showColorFallback: Bool
    
    init(speaker: Speaker?, size: CGFloat = 32, showColorFallback: Bool = true) {
        self.speaker = speaker
        self.size = size
        self.showColorFallback = showColorFallback
    }
    
    var body: some View {
        Group {
            if let speaker = speaker, let imageData = speaker.imageData, let nsImage = NSImage(data: imageData) {
                // Show speaker image
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(colorForSpeaker(speaker).opacity(0.3), lineWidth: 1)
                    )
            } else if let speaker = speaker, showColorFallback {
                // Show color circle with initials as fallback
                Circle()
                    .fill(colorForSpeaker(speaker))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initialsForSpeaker(speaker))
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundColor(.white)
                    )
            } else {
                // No speaker - show placeholder
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: size * 0.6))
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
    
    private func colorForSpeaker(_ speaker: Speaker) -> Color {
        // Use stored color if available
        if let hex = speaker.colorHex, let color = Color(hex: hex) {
            return color
        }
        
        // Fallback to hash-based color
        let colors: [Color] = [.red, .blue, .green, .purple, .orange, .pink, .cyan, .mint, .indigo, .yellow]
        let index = abs(speaker.id.hashValue) % colors.count
        return colors[index]
    }
    
    private func initialsForSpeaker(_ speaker: Speaker) -> String {
        let name = speaker.displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2)).uppercased()
        }
        return "??"
    }
}
