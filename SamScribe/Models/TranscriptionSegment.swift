import Foundation
import SwiftData

@Model
final class TranscriptionSegment {
    var id: UUID
    var text: String
    @Transient var speakerLabel: String? {  // COMPUTED: Get from speaker relationship
        speaker?.displayName
    }
    var embeddingData: Data?  // Store segment's embedding (256 floats = 1024 bytes)
    var confidence: Float
    var startTime: TimeInterval
    var endTime: TimeInterval
    var isPartial: Bool
    var audioSourceType: String  // "microphone" or "appAudio"
    var timestamp: Date

    // Relationships
    var recording: Recording?
    var speaker: Speaker?  // Relationship to Speaker entity

    init(
        id: UUID = UUID(),
        text: String,
        embeddingData: Data? = nil,
        confidence: Float,
        startTime: TimeInterval,
        endTime: TimeInterval,
        isPartial: Bool,
        audioSourceType: String,
        timestamp: Date
    ) {
        self.id = id
        self.text = text
        self.embeddingData = embeddingData
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

        // Convert embedding to Data if present
        let embeddingData = result.embedding.map { Speaker.createEmbeddingData(from: $0) }

        self.init(
            text: result.text,
            embeddingData: embeddingData,
            confidence: result.confidence,
            startTime: result.startTime,
            endTime: result.endTime,
            isPartial: result.isPartial,
            audioSourceType: sourceType,
            timestamp: result.timestamp
        )
    }
}
