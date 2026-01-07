import Foundation
import SwiftData

@Model
final class TranscriptionSegment {
    var id: UUID
    var text: String  // Mutable for editing
    var speakerID: String?
    var speakerLabel: String?
    var confidence: Float
    var startTime: TimeInterval
    var endTime: TimeInterval
    var isPartial: Bool
    var audioSourceType: String  // "microphone" or "appAudio"
    var timestamp: Date

    // Relationship to parent recording
    var recording: Recording?

    init(
        id: UUID = UUID(),
        text: String,
        speakerID: String? = nil,
        speakerLabel: String? = nil,
        confidence: Float,
        startTime: TimeInterval,
        endTime: TimeInterval,
        isPartial: Bool,
        audioSourceType: String,
        timestamp: Date
    ) {
        self.id = id
        self.text = text
        self.speakerID = speakerID
        self.speakerLabel = speakerLabel
        self.confidence = confidence
        self.startTime = startTime
        self.endTime = endTime
        self.isPartial = isPartial
        self.audioSourceType = audioSourceType
        self.timestamp = timestamp
    }

    // Convenience initializer from TranscriptionResult
    convenience init(from result: TranscriptionResult) {
        let sourceType: String = switch result.audioSource {
        case .microphone: "microphone"
        case .appAudio: "appAudio"
        }

        self.init(
            text: result.text,
            speakerID: result.speakerID,
            speakerLabel: result.speakerLabel,
            confidence: result.confidence,
            startTime: result.startTime,
            endTime: result.endTime,
            isPartial: result.isPartial,
            audioSourceType: sourceType,
            timestamp: result.timestamp
        )
    }
}
