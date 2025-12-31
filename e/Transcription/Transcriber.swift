import AVFoundation
import Foundation
import OSLog
import FluidAudio

actor Transcriber {
    private let logger = Logging(name: "Transcriber")

    // Audio processing constants (iOS pattern)
    private static let CHUNK_SECONDS: Float = 10.0
    private static let SAMPLE_RATE: Float = 16000
    private static let CHUNK_SAMPLES = Int(SAMPLE_RATE * CHUNK_SECONDS) // 160,000

    // FluidAudio managers
    private var asrManager: AsrManager?
    private var diarizationManager: DiarizerManager?
    private var isInitialized = false
    private var isTranscribing = false

    // Chunk accumulation buffer (16kHz from AudioInput/ApplicationAudio)
    private var chunkBuffer: [Float] = []
    private var chunkStartTime: Date?

    private var resultHandler: (@Sendable (TranscriptionResult) -> Void)?

    func initialize() async throws {
        guard !isInitialized else {
            logger.info("Transcriber already initialized")
            return
        }

        logger.info("🚀 Starting FluidAudio initialization...")

        let maxRetries = 3
        let retryDelay: UInt64 = 15_000_000_000  // 15 seconds in nanoseconds

        for attempt in 1...maxRetries {
            do {
                logger.info("📥 Attempt \(attempt)/\(maxRetries): Loading models...")

                // Initialize AsrManager
                let asrConfig = ASRConfig()
                let manager = AsrManager(config: asrConfig)

                // Download and load ASR models
                let models = try await AsrModels.downloadAndLoad()
                try await manager.initialize(models: models)

                self.asrManager = manager
                logger.info("✅ AsrManager initialized")

                // Initialize diarization (always enabled)
                logger.info("📥 Loading diarization models...")

                let diarizationConfig = DiarizerConfig(
                    clusteringThreshold: 0.4,
                    minSpeechDuration: 0.2,
                    minSilenceGap: 0.1,
                    debugMode: false
                )

                let diarizer = DiarizerManager(config: diarizationConfig)
                let diarizationModels = try await DiarizerModels.downloadIfNeeded()
                diarizer.initialize(models: diarizationModels)

                self.diarizationManager = diarizer
                logger.info("✅ Diarization enabled")

                isInitialized = true
                logger.info("✅ Transcriber initialized successfully")
                return  // Success - exit retry loop

            } catch {
                logger.error("❌ Attempt \(attempt) failed: \(error)")

                if attempt < maxRetries {
                    logger.info("⏳ Waiting 15 seconds before retry...")
                    try await Task.sleep(nanoseconds: retryDelay)
                } else {
                    logger.error("❌ All \(maxRetries) attempts failed. Giving up.")
                    throw FluidAudioError.modelLoadingFailed(error)
                }
            }
        }
    }

    func startTranscription(
        onResult: @escaping @Sendable (TranscriptionResult) -> Void
    ) async throws {
        guard isInitialized else {
            throw FluidAudioError.notInitialized
        }

        guard !isTranscribing else {
            throw FluidAudioError.alreadyTranscribing
        }

        logger.info("Starting real-time transcription with diarization")

        resultHandler = onResult
        isTranscribing = true

        logger.info("Real-time transcription started")
    }

    func stopTranscription() async throws {
        guard isTranscribing else {
            logger.info("Transcription not currently running")
            return
        }

        logger.info("Stopping transcription")

        // Process any remaining audio in buffer
        if !chunkBuffer.isEmpty {
            logger.info("Processing remaining \(chunkBuffer.count) samples")
            await processChunk(
                samples: chunkBuffer,
                startTime: chunkStartTime ?? Date()
            )
        }

        // Clear buffers
        chunkBuffer.removeAll()
        chunkStartTime = nil

        // Cleanup ASR manager (keeps models cached)
        logger.info("Cleaning up ASR resources")
        asrManager?.cleanup()
        asrManager = nil

        // Cleanup diarization manager (keeps models cached)
        logger.info("Cleaning up diarization resources")
        diarizationManager?.cleanup()
        diarizationManager = nil

        isTranscribing = false
        isInitialized = false
        resultHandler = nil

        logger.info("Transcription stopped and resources cleaned up")
    }

    func processAudioChunk(_ buffer: AVAudioPCMBuffer) async throws {
        guard isTranscribing else {
            return
        }

        // Buffer is already 16kHz mono from AudioInput/ApplicationAudio
        // Extract samples directly
        guard let channelData = buffer.floatChannelData else {
            logger.error("No float channel data in buffer")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Initialize chunk start time on first buffer
        if chunkStartTime == nil {
            chunkStartTime = Date()
        }

        // Accumulate samples (already 16kHz)
        chunkBuffer.append(contentsOf: samples)

        // Process when chunk is full (10 seconds = 160,000 samples)
        if chunkBuffer.count >= Self.CHUNK_SAMPLES {
            let chunkToProcess = chunkBuffer
            let chunkTime = chunkStartTime ?? Date()

            // Check if entire chunk is silent
            let chunkMaxAmplitude = chunkToProcess.map { abs($0) }.max() ?? 0.0
            if chunkMaxAmplitude < 0.001 {
                logger.info("⚠️ ENTIRE CHUNK IS SILENT: \(chunkToProcess.count) samples, max amplitude: \(chunkMaxAmplitude)")
            } else {
                logger.info("✅ Chunk ready for processing: \(chunkToProcess.count) samples, max amplitude: \(String(format: "%.4f", chunkMaxAmplitude))")
            }

            // Reset buffer immediately (prevent concurrent processing)
            chunkBuffer.removeAll()
            chunkStartTime = nil

            // Process chunk (ASR + Diarization)
            await processChunk(samples: chunkToProcess, startTime: chunkTime)
        }
    }

    private func processChunk(samples: [Float], startTime: Date) async {
        guard let asrManager = asrManager else {
            logger.error("AsrManager not initialized")
            return
        }

        do {
            // Check if audio is silent before transcribing
            let maxAmplitude = samples.map { abs($0) }.max() ?? 0.0
            let duration = Float(samples.count) / Self.SAMPLE_RATE

            logger.info("🎤 Transcribing chunk (\(samples.count) samples = \(String(format: "%.1f", duration))s, max amplitude: \(String(format: "%.6f", maxAmplitude)))...")

            if maxAmplitude < 0.001 {
                logger.info("⚠️ AUDIO IS SILENT - Skipping transcription")
                return
            }

            // Step 1: Transcribe chunk
            let asrResult = try await asrManager.transcribe(samples, source: .microphone)

            let cleanedText = asrResult.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !cleanedText.isEmpty else {
                logger.info("⚠️ TRANSCRIPTION RETURNED EMPTY (audio had amplitude \(String(format: "%.6f", maxAmplitude))) - ASR failed to detect speech")
                return
            }

            // Step 2: Diarize chunk
            var speakerID: String? = nil
            var speakerLabel: String? = nil

            if let diarizerManager = diarizationManager {
                logger.info("🔊 Diarizing chunk...")

                do {
                    let diarizationResult = try diarizerManager.performCompleteDiarization(
                        samples,
                        sampleRate: Int(Self.SAMPLE_RATE)
                    )

                    // Step 3: Find speaker who spoke longest
                    if let longestSegment = findLongestSpeaker(from: diarizationResult) {
                        speakerID = longestSegment.speakerId
                        speakerLabel = "Speaker \(longestSegment.speakerId)"
                        let duration = longestSegment.endTimeSeconds - longestSegment.startTimeSeconds
                        logger.info("📍 Longest speaker: \(speakerLabel ?? "Unknown") (\(String(format: "%.1f", duration))s)")
                    }
                } catch {
                    logger.error("Diarization failed: \(error)")
                    // Continue without speaker info
                }
            }

            // Step 4: Create result with speaker attribution
            let result = TranscriptionResult(
                text: cleanedText,
                speakerID: speakerID,
                speakerLabel: speakerLabel,
                confidence: asrResult.confidence,
                startTime: 0.0,
                endTime: TimeInterval(Self.CHUNK_SECONDS),
                isPartial: false,
                audioSource: AudioSourceInfo(
                    type: .microphone,
                    identifier: "chunk",
                    displayName: "Microphone"
                ),
                timestamp: startTime
            )

            logger.info("📝 RESULT: \(speakerLabel ?? "Unknown"): \(cleanedText)")

            // Send to handler
            resultHandler?(result)

        } catch {
            logger.error("Chunk processing failed: \(error)")
        }
    }

    private func findLongestSpeaker(from result: DiarizationResult) -> TimedSpeakerSegment? {
        var longestSegment: TimedSpeakerSegment? = nil
        var maxDuration: Float = 0

        for segment in result.segments {
            let duration = segment.endTimeSeconds - segment.startTimeSeconds
            if duration > maxDuration {
                maxDuration = duration
                longestSegment = segment
            }
        }

        return longestSegment
    }

    func cleanup() async {
        // stopTranscription() already does all the cleanup
        if isTranscribing {
            try? await stopTranscription()
        } else {
            // If not transcribing, still clean up managers
            asrManager?.cleanup()
            asrManager = nil
            diarizationManager?.cleanup()
            diarizationManager = nil
            isInitialized = false
            chunkBuffer.removeAll()
            chunkStartTime = nil
            logger.info("Transcriber cleaned up")
        }
    }

    var status: TranscriptionStatus {
        if !isInitialized {
            return .notInitialized
        } else if isTranscribing {
            return .transcribing
        } else {
            return .ready
        }
    }
}

enum TranscriptionStatus {
    case notInitialized
    case ready
    case transcribing
    case error(Error)

    var isActive: Bool {
        switch self {
        case .transcribing:
            return true
        default:
            return false
        }
    }
}

enum FluidAudioError: Error, LocalizedError {
    case notInitialized
    case alreadyTranscribing
    case sessionNotAvailable
    case modelLoadingFailed(Error)
    case audioProcessingError(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcriber not initialized"
        case .alreadyTranscribing:
            return "Transcription already in progress"
        case .sessionNotAvailable:
            return "Transcriber session not available"
        case .modelLoadingFailed(let error):
            return "Model loading failed: \(error.localizedDescription)"
        case .audioProcessingError(let message):
            return "Audio processing error: \(message)"
        }
    }
}

// Data models (simplified versions of what would be in TranscriptionResult.swift)
struct TranscriptionResult: Sendable {
    let text: String
    let speakerID: String?
    let speakerLabel: String?
    let confidence: Float
    let startTime: TimeInterval
    let endTime: TimeInterval
    let isPartial: Bool
    let audioSource: AudioSourceInfo
    let timestamp: Date

    nonisolated init(
        text: String,
        speakerID: String? = nil,
        speakerLabel: String? = nil,
        confidence: Float,
        startTime: TimeInterval,
        endTime: TimeInterval,
        isPartial: Bool = false,
        audioSource: AudioSourceInfo,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.speakerID = speakerID
        self.speakerLabel = speakerLabel
        self.confidence = confidence
        self.startTime = startTime
        self.endTime = endTime
        self.isPartial = isPartial
        self.audioSource = audioSource
        self.timestamp = timestamp
    }
}

struct AudioSourceInfo: Sendable {
    let type: AudioSourceType
    let identifier: String
    let displayName: String

    enum AudioSourceType {
        case microphone
        case meetingApp
        case systemAudio
    }
}