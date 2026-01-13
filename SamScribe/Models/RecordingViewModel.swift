import Foundation

struct RecordingViewModel: Identifiable, Sendable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date?
    let duration: TimeInterval
    let segmentCount: Int
    let audioFileURL: String?
    var segments: [TranscriptionSegmentViewModel]

    init(from recording: Recording, includeSegments: Bool = false) {
        self.id = recording.id
        self.title = recording.title
        self.startDate = recording.startDate
        self.endDate = recording.endDate
        self.duration = recording.duration
        self.segmentCount = recording.segmentCount
        self.audioFileURL = recording.audioFileURL

        if includeSegments {
            self.segments = recording.segments
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map { TranscriptionSegmentViewModel(from: $0) }
        } else {
            self.segments = []
        }
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
