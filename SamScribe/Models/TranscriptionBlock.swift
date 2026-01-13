import Foundation

struct TranscriptionBlock: Identifiable, Sendable {
    let id: UUID
    let segments: [TranscriptionSegmentViewModel]
    let speaker: Speaker?
    
    // Computed properties
    var combinedText: String {
        segments.map { $0.text }.joined(separator: " ")
    }
    
    var startTime: TimeInterval {
        segments.first?.startTime ?? 0
    }
    
    var endTime: TimeInterval {
        segments.last?.endTime ?? 0
    }
    
    var startTimestamp: Date {
        segments.first?.timestamp ?? Date()
    }
    
    var endTimestamp: Date {
        guard let firstSegment = segments.first else { return Date() }
        let duration = endTime - startTime
        return firstSegment.timestamp.addingTimeInterval(duration)
    }
    
    var averageConfidence: Float {
        guard !segments.isEmpty else { return 0 }
        let total = segments.reduce(0.0) { $0 + $1.confidence }
        return total / Float(segments.count)
    }
    
    init(segments: [TranscriptionSegmentViewModel]) {
        self.id = UUID()
        self.segments = segments
        self.speaker = segments.first?.speaker
    }
    
    // Helper to check if a segment should be grouped with this block
    func canGroupWith(_ segment: TranscriptionSegmentViewModel) -> Bool {
        // Same speaker (or both nil)
        let sameSpeaker = (speaker?.id == segment.speaker?.id) && (speaker != nil || segment.speaker == nil)
        return sameSpeaker
    }
}
