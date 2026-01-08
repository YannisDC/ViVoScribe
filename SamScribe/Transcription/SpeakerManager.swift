import Foundation
import SwiftData
import FluidAudio

@MainActor
final class SpeakerManager {
    private let logger = Logging(name: "SpeakerManager")
    private let modelContext: ModelContext

    // Use FluidAudio's recommended configuration
    private let config = SpeakerUtilities.AssignmentConfig.macOS

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Find or create speaker for new segment
    func assignSpeaker(embedding: [Float], segmentDuration: Float) -> Speaker {
        // Validate embedding first (from SpeakerUtilities)
        guard SpeakerUtilities.validateEmbedding(embedding) else {
            logger.error("Invalid embedding received")
            return createUnknownSpeaker(embedding: embedding)
        }

        let existingSpeakers = fetchAllSpeakers()

        if let match = findBestMatch(embedding: embedding, candidates: existingSpeakers) {
            return match
        }

        return createNewSpeaker(embedding: embedding)
    }

    private func fetchAllSpeakers() -> [Speaker] {
        let descriptor = FetchDescriptor<Speaker>(
            sortBy: [SortDescriptor(\Speaker.speakerNumber, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func findBestMatch(embedding: [Float], candidates: [Speaker]) -> Speaker? {
        guard !candidates.isEmpty else { return nil }

        var bestSpeaker: Speaker?
        var minDistance = Float.infinity

        for candidate in candidates {
            // Use FluidAudio's cosineDistance (optimized with vDSP)
            let distance = SpeakerUtilities.cosineDistance(embedding, candidate.getEmbedding())

            if distance < minDistance {
                minDistance = distance
                bestSpeaker = candidate
            }
        }

        // Check against FluidAudio's recommended threshold (0.65 for macOS)
        if minDistance < config.maxDistanceForAssignment {
            logger.info("Matched speaker with distance: \(minDistance)")
            return bestSpeaker
        }

        logger.info("No match found (min distance: \(minDistance) > threshold: \(config.maxDistanceForAssignment))")
        return nil
    }

    private func createNewSpeaker(embedding: [Float]) -> Speaker {
        let speakers = fetchAllSpeakers()
        let nextNumber = (speakers.map { $0.speakerNumber }.max() ?? 0) + 1

        let speaker = Speaker(
            speakerNumber: nextNumber,
            embeddingData: Speaker.createEmbeddingData(from: embedding)
        )

        modelContext.insert(speaker)
        try? modelContext.save()

        logger.info("Created new speaker: Speaker \(nextNumber)")
        return speaker
    }

    private func createUnknownSpeaker(embedding: [Float]) -> Speaker {
        // For invalid embeddings, create a special "Unknown" speaker
        // This handles the "no speaker detected" case from Transcriber
        let speaker = Speaker(
            speakerNumber: 0,  // Special number for unknown
            embeddingData: Speaker.createEmbeddingData(from: embedding),
            customName: "Unknown Speaker"
        )

        modelContext.insert(speaker)
        try? modelContext.save()

        return speaker
    }

    func renameSpeaker(_ speaker: Speaker, newName: String) {
        speaker.customName = newName.isEmpty ? nil : newName
        speaker.updatedAt = Date()
        try? modelContext.save()

        logger.info("Renamed speaker \(speaker.speakerNumber) to '\(newName)'")
    }
}
