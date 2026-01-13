import Foundation

struct TranscriptionSegmentViewModel: Identifiable, Sendable {
    let id: UUID
    let text: String  // Current text (may be edited)
    let originalText: String  // Original transcription text (falls back to text if not set)
    let speakerLabel: String?
    let speaker: Speaker?
    let confidence: Float
    let startTime: TimeInterval
    let endTime: TimeInterval
    let isPartial: Bool
    let audioSourceType: String
    let timestamp: Date

    init(from segment: TranscriptionSegment) {
        self.id = segment.id
        self.text = segment.text
        // Use originalText if available, otherwise fall back to text (for migration)
        self.originalText = segment.originalText ?? segment.text
        self.speakerLabel = segment.speakerLabel
        self.speaker = segment.speaker
        self.confidence = segment.confidence
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.isPartial = segment.isPartial
        self.audioSourceType = segment.audioSourceType
        self.timestamp = segment.timestamp
    }
}
