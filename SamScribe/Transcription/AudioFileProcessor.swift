import AVFoundation
import Foundation
import OSLog
import FluidAudio

final class AudioFileProcessor {
    private let logger = Logging(name: "AudioFileProcessor")
    private let audioConverter = AudioConverter()
    
    func processAudioFile(
        url: URL,
        transcriber: Transcriber,
        recordingStartDate: Date,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping () -> Void
    ) async throws {
        logger.info("Starting audio file processing: \(url.lastPathComponent)")
        
        // Ensure we have access to the file
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access security-scoped resource")
            throw AudioFileProcessorError.fileReadFailed
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let fileFormat = audioFile.processingFormat
        logger.info("Audio file format: \(fileFormat.sampleRate) Hz, \(fileFormat.channelCount) channels")
        
        // Target format: 16kHz mono Float32 for FluidAudio
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileProcessorError.invalidTargetFormat
        }
        
        // Note: Transcription should be started and callback configured before calling this method
        // This method only processes audio chunks through the already-configured transcriber
        
        // Read and process audio in chunks
        let frameCapacity: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: fileFormat,
            frameCapacity: frameCapacity
        ) else {
            throw AudioFileProcessorError.bufferCreationFailed
        }
        
        let totalFrames = audioFile.length
        var processedFrames: AVAudioFramePosition = 0
        var accumulatedSamples: [Float] = []
        let chunkSize = 160_000 // 10 seconds at 16kHz
        var absoluteTimeOffset: TimeInterval = 0.0  // Track absolute time in the file (in seconds)
        
        // Process audio file - read until we reach the end
        // AVAudioFile.read(into:) throws when it reaches EOF, so we catch that
        while true {
            // Reset buffer length for next read
            buffer.frameLength = 0
            
            // Try to read next chunk
            do {
                try audioFile.read(into: buffer)
            } catch {
                // Reached end of file - break out of loop
                break
            }
            
            // Check if we actually read any frames
            guard buffer.frameLength > 0 else {
                break
            }
            
            // Convert buffer to 16kHz mono
            let samples = try audioConverter.resampleBuffer(buffer)
            accumulatedSamples.append(contentsOf: samples)
            
            // Update progress based on original file frames
            processedFrames += AVAudioFramePosition(buffer.frameLength)
            let progress = Double(processedFrames) / Double(totalFrames)
            Task { @MainActor in
                onProgress(min(progress, 1.0))
            }
            
            // Process chunks when we have enough samples (10 seconds)
            while accumulatedSamples.count >= chunkSize {
                let chunk = Array(accumulatedSamples.prefix(chunkSize))
                accumulatedSamples.removeFirst(chunkSize)
                
                // Create PCM buffer from chunk
                guard let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: AVAudioFrameCount(chunk.count)
                ) else {
                    continue
                }
                
                pcmBuffer.frameLength = AVAudioFrameCount(chunk.count)
                guard let channelData = pcmBuffer.floatChannelData else {
                    continue
                }
                
                // Copy samples to buffer
                for (i, sample) in chunk.enumerated() {
                    channelData[0][i] = sample
                }
                
                // Create transcription buffer with file source
                // For file audio, set chunk start time to represent absolute position in file
                // This allows segments to have correct timestamps
                let chunkStartDate = recordingStartDate.addingTimeInterval(absoluteTimeOffset)
                let transcriptionBuffer = TranscriptionAudioBuffer(
                    buffer: pcmBuffer,
                    timestamp: mach_absolute_time(),
                    source: .fileAudio
                )
                
                // Process chunk through transcriber with the correct start time
                try await transcriber.processAudioChunk(transcriptionBuffer, chunkStartTime: chunkStartDate)
                
                // Update absolute time offset for next chunk (10 seconds per chunk)
                absoluteTimeOffset += 10.0
            }
        }
        
        // Process remaining samples
        if !accumulatedSamples.isEmpty {
            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(accumulatedSamples.count)
            ) else {
                throw AudioFileProcessorError.bufferCreationFailed
            }
            
            pcmBuffer.frameLength = AVAudioFrameCount(accumulatedSamples.count)
            guard let channelData = pcmBuffer.floatChannelData else {
                throw AudioFileProcessorError.bufferCreationFailed
            }
            
            for (i, sample) in accumulatedSamples.enumerated() {
                channelData[0][i] = sample
            }
            
            // For remaining samples, calculate the absolute time offset
            let remainingChunkStartDate = recordingStartDate.addingTimeInterval(absoluteTimeOffset)
            let transcriptionBuffer = TranscriptionAudioBuffer(
                buffer: pcmBuffer,
                timestamp: mach_absolute_time(),
                source: .fileAudio
            )
            
            try await transcriber.processAudioChunk(transcriptionBuffer, chunkStartTime: remainingChunkStartDate)
        }
        
        // Stop transcription
        try await transcriber.stopTranscription()
        
        logger.info("Audio file processing complete: \(url.lastPathComponent)")
        Task { @MainActor in
            onComplete()
        }
    }
}

enum AudioFileProcessorError: Error, LocalizedError {
    case invalidTargetFormat
    case bufferCreationFailed
    case fileReadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidTargetFormat:
            return "Failed to create target audio format"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .fileReadFailed:
            return "Failed to read audio file"
        }
    }
}
