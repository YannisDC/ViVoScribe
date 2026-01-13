import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date?
    var audioFileURL: String?  // Store audio file URL as string for SwiftData compatibility

    // One-to-many relationship with cascade delete
    @Relationship(deleteRule: .cascade, inverse: \TranscriptionSegment.recording)
    var segments: [TranscriptionSegment]

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        audioFileURL: String? = nil,
        segments: [TranscriptionSegment] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.audioFileURL = audioFileURL
        self.segments = segments
    }

    // Computed properties
    var duration: TimeInterval {
        guard let endDate = endDate else {
            return Date().timeIntervalSince(startDate)
        }
        return endDate.timeIntervalSince(startDate)
    }

    var segmentCount: Int {
        segments.count
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
