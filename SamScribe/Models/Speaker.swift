import Foundation
import SwiftData
import FluidAudio

@Model
final class Speaker {
    var id: UUID
    var customName: String?  // User-provided name (optional)
    var speakerNumber: Int   // Auto-assigned: 1, 2, 3... (0 for unknown)
    var embeddingData: Data  // SpeakerManager.embeddingSize (256) floats = 1024 bytes
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \TranscriptionSegment.speaker)
    var segments: [TranscriptionSegment]

    var displayName: String {
        if speakerNumber == 0 {
            return customName ?? "Unknown Speaker"  // Handle "No speaker" case
        }
        return customName ?? "Speaker \(speakerNumber)"
    }

    init(
        id: UUID = UUID(),
        speakerNumber: Int,
        embeddingData: Data,
        customName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.speakerNumber = speakerNumber
        self.embeddingData = embeddingData
        self.customName = customName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.segments = []
    }

    func getEmbedding() -> [Float] {
        // Convert Data back to [Float] array
        embeddingData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func createEmbeddingData(from embedding: [Float]) -> Data {
        // Convert [Float] array to Data for storage
        // Expected size: SpeakerManager.embeddingSize (256) floats = 1024 bytes
        var array = embedding
        return Data(bytes: &array, count: embedding.count * MemoryLayout<Float>.stride)
    }
}
