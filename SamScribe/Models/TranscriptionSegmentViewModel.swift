import Foundation

struct TranscriptionSegmentViewModel: Identifiable, Sendable {
    let id: UUID
    let text: String
    let speakerID: String?
    let speakerLabel: String?
    let speaker: Speaker?  // NEW: Full speaker reference for editing
    let confidence: Float
    let startTime: TimeInterval
    let endTime: TimeInterval
    let isPartial: Bool
    let audioSourceType: String
    let timestamp: Date

    init(from segment: TranscriptionSegment) {
        self.id = segment.id
        self.text = segment.text
        self.speakerID = segment.speakerID
        self.speakerLabel = segment.speakerLabel
        self.speaker = segment.speaker  // NEW: Pass speaker reference
        self.confidence = segment.confidence
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.isPartial = segment.isPartial
        self.audioSourceType = segment.audioSourceType
        self.timestamp = segment.timestamp
    }
}
