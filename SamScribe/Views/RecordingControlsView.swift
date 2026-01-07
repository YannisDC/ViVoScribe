import SwiftUI

struct RecordingControlsView: View {
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isRecording ? "stop.circle.fill" : "waveform")
                .font(.system(size: 16))

            Text(isRecording ? "Stop Transcribing" : "Start Transcribing")
                .font(.body)
                .fontWeight(.medium)
        }
        .foregroundColor(isRecording ? .white : .accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRecording ? Color.red : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isRecording ? Color.clear : Color.accentColor, lineWidth: 1.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isRecording {
                onStopRecording()
            } else {
                onStartRecording()
            }
        }
        .drawingGroup()
        .compositingGroup()
    }
}
