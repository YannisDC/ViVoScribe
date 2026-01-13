import Foundation
import NaturalLanguage
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(MLXLLM)
import MLXLLM
import MLX
import MLXLMCommon
import Hub
import Tokenizers
#endif

#if canImport(LumoKit)
import LumoKit
#endif

/// Service for analyzing transcriptions using Apple's on-device AI capabilities
@MainActor
class TranscriptionAnalyzer: ObservableObject {
    private let logger = Logging(name: "TranscriptionAnalyzer")
    private var conversationMemory: String = "" // Running summary of conversation
    
    #if canImport(LumoKit)
    // LumoKit for RAG
    private var lumoKit: LumoKit?
    #endif
    
    #if canImport(FoundationModels)
    // Store session as Any? to avoid availability issues with stored properties
    private var languageModelSessionStorage: Any?
    
    @available(macOS 26.0, *)
    private var languageModelSession: LanguageModelSession? {
        get {
            return languageModelSessionStorage as? LanguageModelSession
        }
        set {
            languageModelSessionStorage = newValue
        }
    }
    #endif
    
    #if canImport(MLXLLM)
    // MLX Swift LM model context
    private var mlxModelContext: ModelContext?
    private var isMLXModelLoaded = false
    private var mlxModelSetupTask: Task<Void, Never>?
    private var mlxModelLoadFailed = false
    #endif
    
    init() {
        // Don't set up Foundation Models eagerly - prefer MLX Phi model
        // Foundation Models will only be set up as a fallback if MLX fails
        #if canImport(LumoKit)
        setupLumoKit()
        #endif
        #if canImport(MLXLLM)
        // Start MLX model setup and track the task
        mlxModelSetupTask = Task {
            await setupMLXModel()
        }
        #else
        // Only set up Foundation Models if MLX is not available at compile time
        setupFoundationModelSession()
        #endif
    }
    
    #if canImport(LumoKit)
    /// Sets up LumoKit for RAG
    private func setupLumoKit() {
        logger.info("Setting up LumoKit...")
        Task {
            do {
                // Initialize LumoKit with default configuration
                // LumoKit will handle embeddings and vector storage automatically
                let config = VecturaConfig()
                let chunkingConfig = ChunkingConfig()
                self.lumoKit = try await LumoKit(config: config, chunkingConfig: chunkingConfig)
                logger.info("LumoKit initialized successfully")
            } catch {
                logger.error("Failed to initialize LumoKit: \(error.localizedDescription)")
                // Continue without LumoKit, will use fallbacks
            }
        }
    }
    #endif
    
    #if canImport(MLXLLM)
    /// Sets up MLX Swift LM model (Phi-4-mini-instruct or similar)
    private func setupMLXModel() async {
        logger.info("Setting up MLX Swift LM model...")
        
        do {
            // Use a lightweight model like Phi-4-mini-instruct
            // Model will be downloaded automatically on first use
            let modelConfiguration = ModelConfiguration(
                id: "mlx-community/Phi-4-mini-instruct-8bit"
            )
            
            // Create Hub API for downloading models
            let hub = HubApi()
            
            // Load model context using LLMModelFactory
            let context = try await LLMModelFactory.shared.load(
                hub: hub,
                configuration: modelConfiguration,
                progressHandler: { [weak self] progress in
                    self?.logger.info("Model download progress: \(Int(progress.fractionCompleted * 100))%")
                }
            )
            
            self.mlxModelContext = context
            self.isMLXModelLoaded = true
            
            logger.info("MLX Swift LM model (Phi) loaded successfully")
        } catch {
            logger.error("Failed to load MLX model: \(error.localizedDescription)")
            mlxModelLoadFailed = true
            // Only set up Foundation Models as fallback if MLX fails
            logger.info("Setting up Foundation Models as fallback...")
            setupFoundationModelSession()
        }
    }
    #endif
    
    /// Builds a chunk index from transcription blocks using LumoKit
    /// This is the preferred method as blocks already represent semantic units (grouped by speaker)
    /// - Parameter blocks: Array of transcription blocks with metadata
    func buildChunkIndex(from blocks: [TranscriptionBlock]) async {
        logger.info("Building chunk index from \(blocks.count) blocks using LumoKit")
        
        #if canImport(LumoKit)
        guard let lumoKit = lumoKit else {
            logger.error("LumoKit not initialized")
            return
        }
        
        // Create chunks from blocks, combining multiple blocks if needed to reach target size
        // Blocks already represent semantic units (grouped by speaker), so we preserve them when possible
        let chunks = createChunks(from: blocks, targetSize: 1500)
        logger.info("Created \(chunks.count) chunks from \(blocks.count) blocks")
        
        // Create a formatted transcription text with chunk separators
        // LumoKit will handle chunking, but we pre-chunk to preserve metadata
        var transcriptionText = ""
        for chunk in chunks {
            if !transcriptionText.isEmpty {
                transcriptionText += "\n\n---\n\n"
            }
            if let speakerLabel = chunk.speakerLabel, !speakerLabel.isEmpty {
                transcriptionText += "[\(speakerLabel)]: "
            }
            transcriptionText += chunk.text
        }
        
        // Write to temporary file for LumoKit to parse and index
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        
        do {
            try transcriptionText.write(to: tempURL, atomically: true, encoding: .utf8)
            
            // Parse and index using LumoKit
            // LumoKit will handle chunking, embedding generation, and indexing
            try await lumoKit.parseAndIndex(url: tempURL)
            
            logger.info("Successfully indexed transcription using LumoKit")
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            logger.error("Failed to parse and index transcription: \(error.localizedDescription)")
            // Clean up temporary file on error
            try? FileManager.default.removeItem(at: tempURL)
        }
        #else
        logger.info("LumoKit not available, skipping index build")
        #endif
    }
    
    /// Builds a chunk index from transcription segments using LumoKit
    /// - Parameter segments: Array of segments with metadata
    /// - Note: Consider using buildChunkIndex(from blocks:) instead for better semantic grouping
    func buildChunkIndex(from segments: [TranscriptionSegment]) async {
        logger.info("Building chunk index from \(segments.count) segments using LumoKit")
        
        #if canImport(LumoKit)
        guard let lumoKit = lumoKit else {
            logger.error("LumoKit not initialized")
            return
        }
        
        // Combine segments into a single transcription text with metadata markers
        // We'll create chunks and write them to a temporary file for LumoKit to process
        let chunks = createChunks(from: segments, targetSize: 1500)
        logger.info("Created \(chunks.count) chunks from segments")
        
        // Create a formatted transcription text with chunk separators
        // LumoKit will handle chunking, but we pre-chunk to preserve metadata
        var transcriptionText = ""
        for chunk in chunks {
            if !transcriptionText.isEmpty {
                transcriptionText += "\n\n---\n\n"
            }
            if let speakerLabel = chunk.speakerLabel, !speakerLabel.isEmpty {
                transcriptionText += "[\(speakerLabel)]: "
            }
            transcriptionText += chunk.text
        }
        
        // Write to temporary file for LumoKit to parse and index
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        
        do {
            try transcriptionText.write(to: tempURL, atomically: true, encoding: .utf8)
            
            // Parse and index using LumoKit
            // LumoKit will handle chunking, embedding generation, and indexing
            try await lumoKit.parseAndIndex(url: tempURL)
            
            logger.info("Successfully indexed transcription using LumoKit")
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            logger.error("Failed to parse and index transcription: \(error.localizedDescription)")
            // Clean up temporary file on error
            try? FileManager.default.removeItem(at: tempURL)
        }
        #else
        logger.info("LumoKit not available, skipping index build")
        #endif
    }
    
    /// Creates chunks from transcription blocks with target size
    /// Blocks already represent semantic units (grouped by speaker), so we preserve them when possible
    private func createChunks(from blocks: [TranscriptionBlock], targetSize: Int) -> [TranscriptionChunk] {
        var chunks: [TranscriptionChunk] = []
        var currentChunkText = ""
        var currentStartTime: TimeInterval = 0
        var currentStartTimestamp: Date?
        var currentSpeaker: String?
        
        // Sort blocks by timestamp to ensure chronological order
        let sortedBlocks = blocks.sorted(by: { $0.startTimestamp < $1.startTimestamp })
        
        for block in sortedBlocks {
            // Skip blocks with no text or only partial segments
            let blockText = block.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blockText.isEmpty else { continue }
            
            // Get speaker label from block
            let speakerLabel = block.speaker?.displayName
            
            // If adding this block would exceed target size, finalize current chunk
            if !currentChunkText.isEmpty && 
               (currentChunkText.count + blockText.count + 1) > targetSize {
                // Create chunk from accumulated text
                if let startTimestamp = currentStartTimestamp {
                    chunks.append(TranscriptionChunk(
                        id: UUID(),
                        text: currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: currentStartTime,
                        endTime: block.startTime, // End time is start of next block
                        timestamp: startTimestamp,
                        speakerLabel: currentSpeaker
                    ))
                }
                
                // Start new chunk with current block
                currentChunkText = blockText
                currentStartTime = block.startTime
                currentStartTimestamp = block.startTimestamp
                currentSpeaker = speakerLabel
            } else {
                // Add to current chunk
                if currentChunkText.isEmpty {
                    currentStartTime = block.startTime
                    currentStartTimestamp = block.startTimestamp
                    currentSpeaker = speakerLabel
                }
                // Add block text with appropriate separator
                currentChunkText += (currentChunkText.isEmpty ? "" : " ") + blockText
            }
        }
        
        // Add final chunk
        if !currentChunkText.isEmpty, let startTimestamp = currentStartTimestamp {
            let lastBlock = sortedBlocks.last
            let endTime = lastBlock?.endTime ?? currentStartTime
            chunks.append(TranscriptionChunk(
                id: UUID(),
                text: currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: currentStartTime,
                endTime: endTime,
                timestamp: startTimestamp,
                speakerLabel: currentSpeaker
            ))
        }
        
        return chunks
    }
    
    /// Creates chunks from segments with target size
    private func createChunks(from segments: [TranscriptionSegment], targetSize: Int) -> [TranscriptionChunk] {
        var chunks: [TranscriptionChunk] = []
        var currentChunkText = ""
        var currentStartTime: TimeInterval = 0
        var currentStartTimestamp: Date?
        var currentSpeaker: String?
        
        for segment in segments.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard !segment.isPartial else { continue }
            
            let segmentText = segment.text
            let speakerLabel = segment.speaker?.displayName ?? segment.speakerLabel
            
            // If adding this segment would exceed target size, finalize current chunk
            if !currentChunkText.isEmpty && 
               (currentChunkText.count + segmentText.count) > targetSize {
                // Create chunk from accumulated text
                if let startTimestamp = currentStartTimestamp {
                    let endTime = segment.startTime
                    chunks.append(TranscriptionChunk(
                        id: UUID(),
                        text: currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: currentStartTime,
                        endTime: endTime,
                        timestamp: startTimestamp,
                        speakerLabel: currentSpeaker
                    ))
                }
                
                // Start new chunk
                currentChunkText = segmentText
                currentStartTime = segment.startTime
                currentStartTimestamp = segment.timestamp
                currentSpeaker = speakerLabel
            } else {
                // Add to current chunk
                if currentChunkText.isEmpty {
                    currentStartTime = segment.startTime
                    currentStartTimestamp = segment.timestamp
                    currentSpeaker = speakerLabel
                }
                currentChunkText += (currentChunkText.isEmpty ? "" : " ") + segmentText
            }
        }
        
        // Add final chunk
        if !currentChunkText.isEmpty, let startTimestamp = currentStartTimestamp {
            let lastSegment = segments.sorted(by: { $0.timestamp < $1.timestamp }).last { !$0.isPartial }
            let endTime = lastSegment?.endTime ?? currentStartTime
            chunks.append(TranscriptionChunk(
                id: UUID(),
                text: currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: currentStartTime,
                endTime: endTime,
                timestamp: startTimestamp,
                speakerLabel: currentSpeaker
            ))
        }
        
        return chunks
    }
    
    /// Sets up the Foundation Model session if available
    private func setupFoundationModelSession() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            // Check if Foundation Models are available
            if SystemLanguageModel.default.isAvailable {
                // Create a language model session with instructions for transcription analysis
                languageModelSession = LanguageModelSession(model: SystemLanguageModel.default) {
                    Instructions("""
                    You are a helpful assistant that analyzes transcriptions and answers questions about them.
                    Provide clear, concise answers based on the transcription content provided.
                    Focus on the actual content and context of the conversation.
                    """)
                }
                logger.info("Foundation Model session initialized")
            } else {
                logger.info("Foundation Models not available, using NLP fallback")
            }
        } else {
            logger.info("Foundation Models require macOS 26.0+, using NLP fallback")
        }
        #endif
    }
    
    /// Analyzes a transcription and answers a question about it using RAG
    /// - Parameters:
    ///   - transcription: The full transcription text (for fallback)
    ///   - question: The question to ask about the transcription
    /// - Returns: The answer to the question
    func answerQuestion(about transcription: String, question: String) async throws -> String {
        logger.info("🔍 Starting question analysis")
        logger.info("📝 Question: '\(question)'")
        logger.info("📄 Transcription length: \(transcription.count) characters")
        
        // Try RAG approach first (if LumoKit is set up)
        #if canImport(LumoKit)
        if let lumoKit = lumoKit {
            do {
                logger.info("✅ Using LumoKit RAG approach")
                let answer = try await answerWithLumoKitRAG(question: question, lumoKit: lumoKit)
                logger.info("✅ RAG answer generated successfully")
                return answer
            } catch {
                logger.info("⚠️ LumoKit RAG approach failed, falling back: \(error.localizedDescription)")
                // Fall through to full transcription approach
            }
        } else {
            logger.debug("ℹ️ LumoKit not available, skipping RAG")
        }
        #endif
        
        // Fallback to full transcription approach
        logger.info("📄 Using full transcription approach (RAG not available or failed)")
        
        #if canImport(MLXLLM)
        // Prioritize MLX Swift LM (Phi model) - best for Apple Silicon, handles long contexts better
        // First check if MLX is already loaded
        if isMLXModelLoaded, let context = mlxModelContext {
            logger.info("✅ Using MLX Swift LM (Phi) for full transcription")
            let answer = try await answerWithMLXFullTranscription(
                transcription: transcription,
                question: question,
                context: context
            )
            logger.info("✅ MLX full transcription answer generated")
            return answer
        }
        
        // If MLX is not loaded yet, wait for it to finish loading (unless it already failed)
        if !mlxModelLoadFailed, let setupTask = mlxModelSetupTask {
            logger.info("⏳ MLX model still loading, waiting for it to complete...")
            await setupTask.value // Wait for setup to complete
            
            // Check again after waiting
            if isMLXModelLoaded, let context = mlxModelContext {
                logger.info("✅ MLX Swift LM (Phi) loaded, using it for full transcription")
                let answer = try await answerWithMLXFullTranscription(
                    transcription: transcription,
                    question: question,
                    context: context
                )
                logger.info("✅ MLX full transcription answer generated")
                return answer
            }
        }
        
        // Only use Foundation Models if MLX failed to load
        if mlxModelLoadFailed {
            logger.info("⚠️ MLX model failed to load, using Foundation Models as fallback")
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if languageModelSession == nil {
                    setupFoundationModelSession()
                }
                if let session = languageModelSession, SystemLanguageModel.default.isAvailable {
                    let answer = try await answerWithFoundationModel(
                        transcription: transcription,
                        question: question,
                        session: session
                    )
                    logger.info("✅ Foundation Model answer generated")
                    return answer
                }
            }
            #endif
        } else {
            // MLX should be available but didn't load - this shouldn't happen if MLX is available
            logger.info("⚠️ MLX model was expected but not loaded and didn't fail - this is unexpected")
        }
        #endif
        
        #if canImport(FoundationModels)
        // Only try Foundation Models if MLX is not available at compile time
        // (This branch only executes if #if canImport(MLXLLM) was false)
        if #available(macOS 26.0, *) {
            if languageModelSession == nil {
                setupFoundationModelSession()
            }
            if let session = languageModelSession, SystemLanguageModel.default.isAvailable {
                logger.info("Using Foundation Models (MLX not available at compile time)")
                return try await answerWithFoundationModel(
                    transcription: transcription,
                    question: question,
                    session: session
                )
            }
        }
        #endif
        
        // Fallback to NLP-based analysis
        return await analyzeWithNLP(transcription: transcription, question: question)
    }
    
    #if canImport(LumoKit)
    /// Answers question using LumoKit RAG
    private func answerWithLumoKitRAG(question: String, lumoKit: LumoKit) async throws -> String {
        logger.debug("🔍 Starting RAG search for question: '\(question)'")
        
        // Step 1: Search for relevant documents using LumoKit
        let searchResults = try await lumoKit.semanticSearch(
            query: question,
            numResults: 5 // Retrieve top 5 most relevant chunks
        )
        
        logger.info("LumoKit retrieved \(searchResults.count) relevant documents")
        
        guard !searchResults.isEmpty else {
            logger.error("❌ No relevant documents found for question: '\(question)'")
            throw NSError(domain: "TranscriptionAnalyzer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "No relevant documents found"])
        }
        
        // Step 2: Format retrieved chunks
        // LumoKit returns SearchResult objects with chunk.text
        let chunksText = searchResults.map { result in
            result.chunk.text
        }.joined(separator: "\n\n")
        
        // Debug: Log retrieved chunks
        logger.debug("📄 Retrieved chunks (\(chunksText.count) chars):")
        for (index, result) in searchResults.enumerated() {
            let preview = String(result.chunk.text.prefix(100))
            logger.debug("  Chunk \(index + 1): '\(preview)\(result.chunk.text.count > 100 ? "..." : "")'")
        }
        
        // Step 3: Generate answer using LLM with retrieved context
        #if canImport(MLXLLM)
        // Prioritize MLX Swift LM (Phi model) - best for Apple Silicon
        if isMLXModelLoaded, let context = mlxModelContext {
            return try await answerWithRAGAndMLX(
                question: question,
                chunks: chunksText,
                context: context
            )
        }
        
        // If MLX is not loaded yet, wait for it to finish loading (unless it already failed)
        if !mlxModelLoadFailed, let setupTask = mlxModelSetupTask {
            logger.info("MLX model still loading for RAG, waiting for it to complete...")
            await setupTask.value // Wait for setup to complete
            
            // Check again after waiting
            if isMLXModelLoaded, let context = mlxModelContext {
                return try await answerWithRAGAndMLX(
                    question: question,
                    chunks: chunksText,
                    context: context
                )
            }
        }
        
        // Only use Foundation Models if MLX failed to load
        if mlxModelLoadFailed {
            logger.info("MLX model failed to load for RAG, using Foundation Models as fallback")
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if languageModelSession == nil {
                    setupFoundationModelSession()
                }
                if let session = languageModelSession, SystemLanguageModel.default.isAvailable {
                    return try await answerWithRAGAndFoundationModel(
                        question: question,
                        chunks: chunksText,
                        session: session
                    )
                }
            }
            #endif
        }
        #endif
        
        #if canImport(FoundationModels)
        // Only try Foundation Models if MLX is not available at compile time
        // (This branch only executes if #if canImport(MLXLLM) was false)
        if #available(macOS 26.0, *) {
            if languageModelSession == nil {
                setupFoundationModelSession()
            }
            if let session = languageModelSession, SystemLanguageModel.default.isAvailable {
                logger.info("Using Foundation Models for RAG (MLX not available at compile time)")
                return try await answerWithRAGAndFoundationModel(
                    question: question,
                    chunks: chunksText,
                    session: session
                )
            }
        }
        #endif
        
        // Fallback: Use NLP with retrieved chunks
        let chunksTextForNLP = searchResults.map { $0.chunk.text }.joined(separator: " ")
        return await analyzeWithNLP(transcription: chunksTextForNLP, question: question)
    }
    #endif
    
    #if canImport(MLXLLM)
    /// Answers question using MLX Swift LM with full transcription (when index not built)
    private func answerWithMLXFullTranscription(
        transcription: String,
        question: String,
        context: ModelContext
    ) async throws -> String {
        // Phi-4-mini-instruct works better with structured prompts and has context limits
        // Approximate: 1 token ≈ 4 characters, safe limit ~16,000 characters (~4,000 tokens)
        // Reserve space for prompt structure and response
        let maxContextLength = 16_000
        let questionLength = question.count
        let promptOverhead = 500 // Overhead for prompt structure
        
        let transcriptionToUse: String
        if transcription.count > (maxContextLength - questionLength - promptOverhead) {
            logger.info("⚠️ Transcription too long (\(transcription.count) chars), truncating to \(maxContextLength - questionLength - promptOverhead) chars")
            // Truncate to fit, but try to keep it at sentence boundaries
            let truncated = String(transcription.prefix(maxContextLength - questionLength - promptOverhead))
            if let lastSentenceEnd = truncated.lastIndex(where: { ".!?".contains($0) }) {
                transcriptionToUse = String(truncated[..<truncated.index(after: lastSentenceEnd)])
            } else {
                transcriptionToUse = truncated
            }
        } else {
            transcriptionToUse = transcription
        }
        
        // Use a more structured prompt format for instruction-following models
        let prompt = """
        You are a helpful assistant that analyzes transcriptions and answers questions about them.

        Transcription:
        \(transcriptionToUse)

        Question: \(question)

        Answer:
        """
        
        logger.debug("🤖 MLX Full Transcription - Prompt length: \(prompt.count) chars")
        logger.debug("📝 Question: '\(question)'")
        logger.debug("📄 Transcription length: \(transcriptionToUse.count) chars")
        logger.debug("📄 Transcription preview: '\(String(transcriptionToUse.prefix(200)))...'")
        
        do {
            // Create input from prompt
            let userInput = UserInput(prompt: .text(prompt))
            let input = try await context.processor.prepare(input: userInput)
            
            // Generate parameters optimized for instruction-following
            // Lower temperature for more focused, deterministic responses
            let generateParams = GenerateParameters(
                maxTokens: 512, // Increased for better answers
                temperature: 0.3, // Lower temperature for more focused responses
                topP: 0.95,
                repetitionPenalty: 1.15, // Stronger penalty to prevent repetition
                repetitionContextSize: 128 // Check more context for repetition
            )
            
            logger.debug("⚙️ Generation params: maxTokens=\(generateParams.maxTokens), temp=\(generateParams.temperature), topP=\(generateParams.topP)")
            
            // Generate response using AsyncStream-based API
            var generatedText = ""
            var lastChunk = ""
            var repetitionCount = 0
            var chunkCount = 0
            let stream = try generate(
                input: input,
                cache: nil,
                parameters: generateParams,
                context: context
            )
            
            logger.debug("🔄 Starting generation stream...")
            
            // Collect all generated chunks with repetition detection and garbage detection
            var consecutiveSmallChunks = 0
            var lastFewChunks: [String] = []
            let maxRecentChunks = 10
            
            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    chunkCount += 1
                    logger.debug("📦 Chunk #\(chunkCount): '\(text)' (length: \(text.count))")
                    
                    // Track recent chunks for pattern detection
                    lastFewChunks.append(text)
                    if lastFewChunks.count > maxRecentChunks {
                        lastFewChunks.removeFirst()
                    }
                    
                    // Detect if we're getting too many tiny fragments (likely garbage output)
                    if text.count <= 2 {
                        consecutiveSmallChunks += 1
                        if consecutiveSmallChunks > 20 {
                            logger.info("🛑 Stopping generation - too many small fragments (likely garbage output)")
                            break
                        }
                    } else {
                        consecutiveSmallChunks = 0
                    }
                    
                    // Check for repetition
                    if text == lastChunk {
                        repetitionCount += 1
                        logger.debug("⚠️ Repetition detected (count: \(repetitionCount)): '\(text)'")
                        if repetitionCount > 3 {
                            logger.info("🛑 Stopping generation due to repetition (count: \(repetitionCount))")
                            break
                        }
                    } else {
                        if repetitionCount > 0 {
                            logger.debug("✅ Repetition cleared")
                        }
                        repetitionCount = 0
                    }
                    lastChunk = text
                    generatedText += text
                    
                    // Early stopping if we have a reasonable answer and detect end markers
                    if generatedText.count > 50 {
                        let trimmed = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Check for natural sentence endings
                        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
                            // If we have a complete sentence and recent chunks are getting repetitive or small
                            if consecutiveSmallChunks > 5 {
                                logger.debug("✅ Early stopping - complete answer detected with trailing fragments")
                                break
                            }
                        }
                    }
                case .info(let info):
                    // Log generation info if needed
                    logger.debug("ℹ️ Generation info: \(info)")
                case .toolCall:
                    // Not used for Q&A
                    logger.debug("🔧 Tool call received (ignored)")
                    break
                }
            }
            
            logger.debug("✅ Generation complete. Total chunks: \(chunkCount), Raw text length: \(generatedText.count)")
            logger.debug("📄 Raw generated text: '\(generatedText)'")
            
            // Clean up the answer: remove special tokens and trim
            let answer = cleanMLXOutput(generatedText.isEmpty ? "No response generated" : generatedText)
            
            logger.debug("🧹 Cleaned text length: \(answer.count)")
            logger.debug("📄 Cleaned text: '\(answer)'")
            
            // Update conversation memory
            updateConversationMemory(question: question, answer: answer)
            
            logger.info("MLX Swift LM response generated: \(answer.count) characters")
            return answer
        } catch {
            logger.error("❌ MLX Swift LM generation failed: \(error.localizedDescription)")
            logger.error("Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            throw error
        }
    }
    
    /// Answers question using RAG with MLX Swift LM
    private func answerWithRAGAndMLX(
        question: String,
        chunks: String,
        context: ModelContext
    ) async throws -> String {
        // Limit chunks size to fit in context window
        let maxChunksLength = 12_000 // Reserve space for prompt and response
        let chunksToUse: String
        if chunks.count > maxChunksLength {
            logger.info("⚠️ Chunks too long (\(chunks.count) chars), truncating to \(maxChunksLength) chars")
            chunksToUse = String(chunks.prefix(maxChunksLength))
        } else {
            chunksToUse = chunks
        }
        
        // Use a more structured prompt format for instruction-following models
        let prompt = """
        You are a helpful assistant that analyzes transcriptions and answers questions about them.

        Relevant excerpts from the transcription:
        \(chunksToUse)

        Question: \(question)

        Answer:
        """
        
        logger.debug("🤖 MLX RAG - Prompt length: \(prompt.count) chars")
        logger.debug("📝 Question: '\(question)'")
        logger.debug("📄 Chunks preview: '\(String(chunksToUse.prefix(200)))...'")
        logger.debug("📊 Chunks total length: \(chunksToUse.count) chars")
        
        do {
            // Create input from prompt
            let userInput = UserInput(prompt: .text(prompt))
            let input = try await context.processor.prepare(input: userInput)
            
            // Generate parameters optimized for instruction-following
            let generateParams = GenerateParameters(
                maxTokens: 512, // Increased for better answers
                temperature: 0.3, // Lower temperature for more focused responses
                topP: 0.95,
                repetitionPenalty: 1.15, // Stronger penalty to prevent repetition
                repetitionContextSize: 128 // Check more context for repetition
            )
            
            logger.debug("⚙️ Generation params: maxTokens=\(generateParams.maxTokens), temp=\(generateParams.temperature), topP=\(generateParams.topP)")
            
            // Generate response using AsyncStream-based API
            var generatedText = ""
            var lastChunk = ""
            var repetitionCount = 0
            var chunkCount = 0
            let stream = try generate(
                input: input,
                cache: nil,
                parameters: generateParams,
                context: context
            )
            
            logger.debug("🔄 Starting RAG generation stream...")
            
            // Collect all generated chunks with repetition detection and garbage detection
            var consecutiveSmallChunks = 0
            var lastFewChunks: [String] = []
            let maxRecentChunks = 10
            
            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    chunkCount += 1
                    logger.debug("📦 Chunk #\(chunkCount): '\(text)' (length: \(text.count))")
                    
                    // Track recent chunks for pattern detection
                    lastFewChunks.append(text)
                    if lastFewChunks.count > maxRecentChunks {
                        lastFewChunks.removeFirst()
                    }
                    
                    // Detect if we're getting too many tiny fragments (likely garbage output)
                    if text.count <= 2 {
                        consecutiveSmallChunks += 1
                        if consecutiveSmallChunks > 20 {
                            logger.info("🛑 Stopping generation - too many small fragments (likely garbage output)")
                            break
                        }
                    } else {
                        consecutiveSmallChunks = 0
                    }
                    
                    // Check for repetition
                    if text == lastChunk {
                        repetitionCount += 1
                        logger.debug("⚠️ Repetition detected (count: \(repetitionCount)): '\(text)'")
                        if repetitionCount > 3 {
                            logger.info("🛑 Stopping generation due to repetition (count: \(repetitionCount))")
                            break
                        }
                    } else {
                        if repetitionCount > 0 {
                            logger.debug("✅ Repetition cleared")
                        }
                        repetitionCount = 0
                    }
                    lastChunk = text
                    generatedText += text
                    
                    // Early stopping if we have a reasonable answer and detect end markers
                    if generatedText.count > 50 {
                        let trimmed = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Check for natural sentence endings
                        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
                            // If we have a complete sentence and recent chunks are getting repetitive or small
                            if consecutiveSmallChunks > 5 {
                                logger.debug("✅ Early stopping - complete answer detected with trailing fragments")
                                break
                            }
                        }
                    }
                case .info(let info):
                    // Log generation info if needed
                    logger.debug("ℹ️ Generation info: \(info)")
                case .toolCall:
                    // Not used for Q&A
                    logger.debug("🔧 Tool call received (ignored)")
                    break
                }
            }
            
            logger.debug("✅ RAG generation complete. Total chunks: \(chunkCount), Raw text length: \(generatedText.count)")
            logger.debug("📄 Raw generated text: '\(generatedText)'")
            
            // Clean up the answer: remove special tokens and trim
            let answer = cleanMLXOutput(generatedText.isEmpty ? "No response generated" : generatedText)
            
            logger.debug("🧹 Cleaned text length: \(answer.count)")
            logger.debug("📄 Cleaned text: '\(answer)'")
            
            // Update conversation memory
            updateConversationMemory(question: question, answer: answer)
            
            logger.info("MLX Swift LM response generated: \(answer.count) characters")
            return answer
        } catch {
            logger.error("❌ MLX Swift LM RAG generation failed: \(error.localizedDescription)")
            logger.error("Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            throw error
        }
    }
    #endif
    
    #if canImport(FoundationModels)
    /// Answers question using RAG with Foundation Models
    @available(macOS 26.0, *)
    private func answerWithRAGAndFoundationModel(
        question: String,
        chunks: String,
        session: LanguageModelSession
    ) async throws -> String {
        let prompt = """
        Based on the following relevant excerpts from a transcription, please answer this question: \(question)
        
        Relevant excerpts:
        \(chunks)
        
        Question: \(question)
        
        Please provide a clear and concise answer.
        """
        
        logger.debug("🤖 Foundation Models RAG - Prompt length: \(prompt.count) chars")
        logger.debug("📝 Question: '\(question)'")
        logger.debug("📄 Chunks preview: '\(String(chunks.prefix(200)))...'")
        logger.debug("📊 Chunks total length: \(chunks.count) chars")
        
        do {
            logger.debug("🔄 Sending request to Foundation Model...")
            let response = try await session.respond(to: prompt)
            let answer = String(describing: response)
            
            logger.debug("✅ Foundation Model response received")
            logger.debug("📄 Raw response: '\(answer)'")
            logger.debug("📊 Response length: \(answer.count) chars")
            
            // Update conversation memory
            updateConversationMemory(question: question, answer: answer)
            
            return answer
        } catch {
            logger.error("❌ RAG with Foundation Model failed: \(error.localizedDescription)")
            logger.error("Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            throw error
        }
    }
    #endif
    
    /// Cleans MLX model output by removing special tokens and fixing formatting
    private func cleanMLXOutput(_ text: String) -> String {
        logger.debug("🧹 Cleaning MLX output - Input length: \(text.count) chars")
        logger.debug("📄 Input text: '\(text)'")
        
        var cleaned = text
        let originalLength = cleaned.count
        
        // Remove common special tokens
        let specialTokens = [
            "<|end|>",
            "<|endoftext|>",
            "<|end_of_text|>",
            "<|user|>",
            "<|assistant|>",
            "<|system|>",
            "<|im_start|>",
            "<|im_end|>"
        ]
        
        var removedTokens: [String] = []
        for token in specialTokens {
            if cleaned.contains(token) {
                removedTokens.append(token)
                cleaned = cleaned.replacingOccurrences(of: token, with: "")
            }
        }
        
        if !removedTokens.isEmpty {
            logger.debug("🗑️ Removed special tokens: \(removedTokens.joined(separator: ", "))")
        }
        
        // Remove any content after these tokens (they indicate end of response)
        if let endIndex = cleaned.range(of: "<|") {
            let removed = String(cleaned[endIndex.lowerBound...])
            cleaned = String(cleaned[..<endIndex.lowerBound])
            logger.debug("✂️ Removed content after '<|': '\(removed.prefix(50))...'")
        }
        
        // Remove excessive whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove repeated periods/spaces (common in repetition loops)
        var previousChar: Character?
        var result = ""
        var consecutivePeriods = 0
        var removedPeriods = 0
        var removedSpaces = 0
        
        for char in cleaned {
            if char == "." {
                consecutivePeriods += 1
                if consecutivePeriods <= 1 {
                    result.append(char)
                } else {
                    removedPeriods += 1
                }
            } else if char == " " && previousChar == " " {
                // Skip consecutive spaces
                removedSpaces += 1
                continue
            } else {
                consecutivePeriods = 0
                result.append(char)
            }
            previousChar = char
        }
        
        if removedPeriods > 0 {
            logger.debug("🗑️ Removed \(removedPeriods) consecutive periods")
        }
        if removedSpaces > 0 {
            logger.debug("🗑️ Removed \(removedSpaces) consecutive spaces")
        }
        
        // Remove trailing repetition patterns (e.g., "I thought I was . I thought I was .")
        let lines = result.components(separatedBy: "\n")
        var uniqueLines: [String] = []
        var seenLines: Set<String> = []
        var duplicateLines = 0
        
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !seenLines.contains(trimmed) {
                uniqueLines.insert(trimmed, at: 0)
                seenLines.insert(trimmed)
            } else if seenLines.contains(trimmed) {
                // If we see a duplicate, stop adding more (likely repetition loop)
                duplicateLines += 1
                logger.debug("🔄 Found duplicate line, stopping: '\(trimmed.prefix(50))...'")
                break
            }
        }
        
        if duplicateLines > 0 {
            logger.debug("🔄 Removed \(duplicateLines) duplicate line(s)")
        }
        
        let finalResult = uniqueLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        logger.debug("✅ Cleaning complete - Output length: \(finalResult.count) chars (reduced from \(originalLength))")
        logger.debug("📄 Final cleaned text: '\(finalResult)'")
        
        return finalResult
    }
    
    /// Updates conversation memory with Q&A pair
    private func updateConversationMemory(question: String, answer: String) {
        let memoryEntry = """
        Q: \(question)
        A: \(answer)
        
        """
        conversationMemory += memoryEntry
        
        // Limit memory size (keep last ~2000 chars)
        if conversationMemory.count > 2000 {
            conversationMemory = String(conversationMemory.suffix(2000))
        }
    }
    
    /// Clears the conversation memory
    func clearConversationMemory() {
        conversationMemory = ""
    }
    
    #if canImport(LumoKit)
    /// Clears the LumoKit index
    func clearIndex() async {
        // LumoKit manages its own index, so clearing might require reinitialization
        // For now, we'll just log that the index should be rebuilt
        logger.info("To clear LumoKit index, rebuild it with buildChunkIndex(from:)")
    }
    #endif
    
    #if canImport(FoundationModels)
    /// Answers questions using Apple Foundation Models
    @available(macOS 26.0, *)
    private func answerWithFoundationModel(
        transcription: String,
        question: String,
        session: LanguageModelSession
    ) async throws -> String {
        logger.debug("🤖 Foundation Model - Starting answer generation")
        logger.debug("📝 Question: '\(question)'")
        
        // Clean the transcription for better analysis
        let cleanedTranscription = cleanTranscription(transcription)
        logger.debug("📄 Transcription length: \(transcription.count) chars, cleaned: \(cleanedTranscription.count) chars")
        
        // Check transcription length - Foundation Models have context limits
        // Approximate: 1 token ≈ 4 characters, safe limit ~40,000 characters (~10,000 tokens)
        let maxContextLength = 40_000
        let questionLength = question.count
        let promptOverhead = 200 // Approximate overhead for prompt structure
        
        if cleanedTranscription.count > (maxContextLength - questionLength - promptOverhead) {
            logger.info("⚠️ Transcription too long (\(cleanedTranscription.count) chars), using summarization approach")
            return try await answerWithLongTranscription(
                transcription: cleanedTranscription,
                question: question,
                session: session
            )
        }
        
        // Create a prompt that includes the transcription and question
        let prompt = """
        Based on the following transcription, please answer this question: \(question)
        
        Transcription:
        \(cleanedTranscription)
        
        Please provide a clear and concise answer based on the transcription content.
        """
        
        logger.debug("📝 Prompt length: \(prompt.count) chars")
        logger.debug("📄 Prompt preview: '\(String(prompt.prefix(300)))...'")
        
        do {
            logger.debug("🔄 Sending request to Foundation Model...")
            // Get response from Foundation Model
            let response = try await session.respond(to: prompt)
            let answer = String(describing: response)
            
            logger.info("✅ Foundation Model response received")
            logger.debug("📄 Raw response: '\(answer)'")
            logger.debug("📊 Response length: \(answer.count) chars")
            
            return answer
        } catch {
            logger.error("❌ Foundation Model error: \(error.localizedDescription)")
            logger.error("Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            
            // If context window error, try summarization approach
            if error.localizedDescription.contains("context window") || error.localizedDescription.contains("Exceeded") {
                logger.info("⚠️ Context window exceeded, falling back to summarization approach")
                return try await answerWithLongTranscription(
                    transcription: cleanedTranscription,
                    question: question,
                    session: session
                )
            }
            // Fallback to NLP if Foundation Model fails
            logger.debug("🔄 Falling back to NLP analysis")
            return await analyzeWithNLP(transcription: transcription, question: question)
        }
    }
    
    /// Handles long transcriptions by creating a summary first, then answering
    @available(macOS 26.0, *)
    private func answerWithLongTranscription(
        transcription: String,
        question: String,
        session: LanguageModelSession
    ) async throws -> String {
        logger.debug("📏 Long transcription handler - Input length: \(transcription.count) chars")
        
        // Step 1: Create a summary of the transcription
        logger.info("📝 Creating summary of long transcription...")
        let summaryPrompt = """
        Please provide a comprehensive summary of the following transcription. 
        Focus on the main topics, key points, important information, and any notable details.
        Keep the summary detailed enough to answer questions about the content.
        
        Transcription:
        \(transcription)
        """
        
        logger.debug("📄 Summary prompt length: \(summaryPrompt.count) chars")
        
        let summary: String
        do {
            logger.debug("🔄 Requesting summary from Foundation Model...")
            let summaryResponse = try await session.respond(to: summaryPrompt)
            summary = String(describing: summaryResponse)
            logger.info("✅ Summary created: \(summary.count) characters")
            logger.debug("📄 Summary preview: '\(String(summary.prefix(300)))...'")
        } catch {
            logger.error("❌ Failed to create summary: \(error.localizedDescription)")
            logger.error("Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            // If summarization also fails, use a truncated version
            let truncated = String(transcription.prefix(30_000)) + "... [transcription truncated]"
            summary = truncated
            logger.info("⚠️ Using truncated transcription as fallback summary")
        }
        
        // Step 2: Answer the question using the summary
        // If the question is specific, also try to extract relevant chunks
        let answerPrompt = """
        Based on the following summary of a transcription, please answer this question: \(question)
        
        Summary:
        \(summary)
        
        Please provide a clear and concise answer. If the summary doesn't contain enough detail to answer the question, please indicate that.
        """
        
        logger.debug("📝 Answer prompt length: \(answerPrompt.count) chars")
        logger.debug("📄 Answer prompt preview: '\(String(answerPrompt.prefix(300)))...'")
        
        do {
            logger.debug("🔄 Requesting answer from Foundation Model...")
            let response = try await session.respond(to: answerPrompt)
            let answer = String(describing: response)
            logger.debug("✅ Answer received: \(answer.count) chars")
            logger.debug("📄 Answer: '\(answer)'")
            return answer
        } catch {
            logger.error("❌ Failed to answer with summary: \(error.localizedDescription)")
            logger.error("Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            // Final fallback to NLP
            logger.debug("🔄 Falling back to NLP analysis")
            return await analyzeWithNLP(transcription: transcription, question: question)
        }
    }
    #endif
    
    /// Basic analysis using NaturalLanguage framework
    /// This is a placeholder until Apple Foundation Models are available
    private func analyzeWithNLP(transcription: String, question: String) async -> String {
        let questionLower = question.lowercased()
        
        // Remove speaker labels and timestamps for better analysis
        let cleanedTranscription = cleanTranscription(transcription)
        
        // Use NaturalLanguage framework for better analysis
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .sentimentScore])
        tagger.string = cleanedTranscription
        
        // Extract named entities (people, organizations, places)
        var entities: [String] = []
        var importantNouns: [String] = []
        var importantVerbs: [String] = []
        
        tagger.enumerateTags(in: cleanedTranscription.startIndex..<cleanedTranscription.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag, tag != .otherWord {
                let entity = String(cleanedTranscription[tokenRange])
                if entity.count > 2 && !entity.lowercased().contains("speaker") {
                    entities.append(entity)
                }
            }
            return true
        }
        
        // Extract important nouns and verbs
        tagger.enumerateTags(in: cleanedTranscription.startIndex..<cleanedTranscription.endIndex, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if let tag = tag {
                let word = String(cleanedTranscription[tokenRange]).lowercased()
                // Filter out common words and UI-related terms
                let stopWords = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "play", "forward", "backward", "brain", "button", "click"]
                
                if !stopWords.contains(word) && word.count > 3 {
                    if tag == .noun {
                        importantNouns.append(word)
                    } else if tag == .verb {
                        importantVerbs.append(word)
                    }
                }
            }
            return true
        }
        
        // Answer based on question type
        if questionLower.contains("what") && (questionLower.contains("about") || questionLower.contains("discuss")) {
            return answerWhatAbout(transcription: cleanedTranscription, entities: entities, nouns: importantNouns)
        }
        
        if questionLower.contains("who") || questionLower.contains("speaker") {
            let speakers = extractSpeakers(from: transcription)
            if !speakers.isEmpty {
                return "The conversation involves the following speakers: \(speakers.joined(separator: ", "))."
            }
            // Try to extract names from entities
            let names = entities.filter { $0.count > 2 && $0.prefix(1).uppercased() == String($0.prefix(1)) }
            if !names.isEmpty {
                return "The conversation mentions: \(Array(Set(names)).prefix(5).joined(separator: ", "))."
            }
        }
        
        if questionLower.contains("when") || questionLower.contains("time") {
            return "Please refer to the timestamps in the transcript for specific times. The conversation duration and timing information is available in the transcript view."
        }
        
        if questionLower.contains("why") || questionLower.contains("reason") {
            return answerWhy(transcription: cleanedTranscription, verbs: importantVerbs)
        }
        
        if questionLower.contains("how") {
            return answerHow(transcription: cleanedTranscription, verbs: importantVerbs)
        }
        
        // General question - provide a summary
        return answerGeneral(transcription: cleanedTranscription, entities: entities, nouns: importantNouns)
    }
    
    /// Clean transcription text by removing speaker labels and timestamps
    private func cleanTranscription(_ text: String) -> String {
        // Remove speaker labels like [Speaker 1]: or [Name]:
        var cleaned = text
        let speakerPattern = #"\[[^\]]+\]:\s*"#
        if let regex = try? NSRegularExpression(pattern: speakerPattern, options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Remove timestamps like / 0:20
        let timestampPattern = #"/\s*\d+:\d+"#
        if let regex = try? NSRegularExpression(pattern: timestampPattern, options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Answer "what is this about" questions
    private func answerWhatAbout(transcription: String, entities: [String], nouns: [String]) -> String {
        // Get most frequent important nouns (topics)
        let nounCounts = Dictionary(grouping: nouns, by: { $0 }).mapValues { $0.count }
        let topTopics = nounCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        
        // Extract key sentences for context
        let sentences = transcription.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { $0.trimmingCharacters(in: .whitespaces).count > 20 }
        let keySentences = sentences.prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }
        
        if !topTopics.isEmpty {
            var answer = "This conversation primarily discusses "
            if topTopics.count == 1 {
                answer += topTopics[0]
            } else if topTopics.count == 2 {
                answer += "\(topTopics[0]) and \(topTopics[1])"
            } else {
                answer += topTopics.dropLast().joined(separator: ", ") + ", and \(topTopics.last!)"
            }
            answer += "."
            
            if !keySentences.isEmpty {
                answer += "\n\nKey points include: " + keySentences.joined(separator: " ")
            }
            
            return answer
        }
        
        return "The conversation covers various topics. Please review the full transcript for detailed information."
    }
    
    /// Answer "why" questions
    private func answerWhy(transcription: String, verbs: [String]) -> String {
        // Look for causal language patterns
        let causalWords = ["because", "due to", "since", "as a result", "therefore", "reason"]
        let sentences = transcription.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let lowerSentence = sentence.lowercased()
            if causalWords.contains(where: { lowerSentence.contains($0) }) {
                return sentence.trimmingCharacters(in: .whitespaces) + "."
            }
        }
        
        return "The transcript discusses various reasons and explanations. Please review the relevant sections for specific details."
    }
    
    /// Answer "how" questions
    private func answerHow(transcription: String, verbs: [String]) -> String {
        // Look for process/action language
        let processWords = ["by", "through", "using", "via", "method", "process", "way"]
        let sentences = transcription.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let lowerSentence = sentence.lowercased()
            if processWords.contains(where: { lowerSentence.contains($0) }) && sentence.count > 30 {
                return sentence.trimmingCharacters(in: .whitespaces) + "."
            }
        }
        
        return "The transcript describes various processes and methods. Please review the relevant sections for specific details."
    }
    
    /// Answer general questions
    private func answerGeneral(transcription: String, entities: [String], nouns: [String]) -> String {
        // Get key topics
        let nounCounts = Dictionary(grouping: nouns, by: { $0 }).mapValues { $0.count }
        let topTopics = nounCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        
        // Get first few sentences as summary
        let sentences = transcription.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { $0.trimmingCharacters(in: .whitespaces).count > 15 }
        let summarySentences = sentences.prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }
        
        var answer = ""
        if !summarySentences.isEmpty {
            answer = summarySentences.joined(separator: ". ") + "."
        } else if !topTopics.isEmpty {
            answer = "The conversation discusses \(topTopics.joined(separator: ", "))."
        } else {
            answer = "Based on the transcription, this appears to be a conversation covering multiple topics. Please review the full transcript for complete details."
        }
        
        return answer
    }
    
    /// Extracts speaker mentions from transcription
    private func extractSpeakers(from text: String) -> [String] {
        // Simple pattern matching for speaker labels
        // In a real implementation, this would use the speaker data from the model
        let pattern = #"Speaker \d+"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        var speakers: Set<String> = []
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = Range(match!.range, in: text) {
                speakers.insert(String(text[matchRange]))
            }
        }
        
        return Array(speakers).sorted()
    }
    
    /// Summarizes the transcription
    func summarize(transcription: String) async throws -> String {
        logger.info("Generating summary of transcription")
        
        #if canImport(FoundationModels)
        // Try to use Foundation Models if available
        if #available(macOS 26.0, *) {
            if let session = languageModelSession, SystemLanguageModel.default.isAvailable {
                let cleanedTranscription = cleanTranscription(transcription)
                
                // Check if transcription is too long
                let maxContextLength = 40_000
                let promptOverhead = 200
                
                if cleanedTranscription.count > (maxContextLength - promptOverhead) {
                    // For very long transcriptions, create a summary in chunks
                    logger.info("Transcription too long for single summary, using chunked approach")
                    return try await summarizeLongTranscription(
                        transcription: cleanedTranscription,
                        session: session
                    )
                }
                
                let prompt = """
                Please provide a comprehensive summary of the following transcription. 
                Focus on the main topics, key points, and important information discussed.
                
                Transcription:
                \(cleanedTranscription)
                """
                
                do {
                    let response = try await session.respond(to: prompt)
                    logger.info("Foundation Model summary generated")
                    // Response is a String directly
                    return String(describing: response)
                } catch {
                    logger.error("Foundation Model summarization error: \(error.localizedDescription)")
                    // If context error, try chunked approach
                    if error.localizedDescription.contains("context window") || error.localizedDescription.contains("Exceeded") {
                        return try await summarizeLongTranscription(
                            transcription: cleanedTranscription,
                            session: session
                        )
                    }
                    // Fallback to basic summary
                }
            }
        }
        #endif
        
        // Fallback to basic summary
        let wordCount = transcription.split(separator: " ").count
        let sentenceCount = transcription.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" }).count
        
        return """
        Transcription Summary:
        - Word count: \(wordCount)
        - Approximate sentences: \(sentenceCount)
        
        Please review the full transcript for detailed information.
        """
    }
    
    #if canImport(FoundationModels)
    /// Summarizes a long transcription by processing it in chunks
    @available(macOS 26.0, *)
    private func summarizeLongTranscription(
        transcription: String,
        session: LanguageModelSession
    ) async throws -> String {
        // Split transcription into manageable chunks (approximately 30,000 chars each)
        let chunkSize = 30_000
        let chunks = transcription.chunked(into: chunkSize)
        
        logger.info("Summarizing \(chunks.count) chunks")
        
        var chunkSummaries: [String] = []
        
        // Summarize each chunk
        for (index, chunk) in chunks.enumerated() {
            logger.info("Summarizing chunk \(index + 1)/\(chunks.count)")
            let chunkPrompt = """
            Please provide a concise summary of this portion of a transcription:
            
            \(chunk)
            """
            
            do {
                let response = try await session.respond(to: chunkPrompt)
                chunkSummaries.append(String(describing: response))
            } catch {
                logger.error("Failed to summarize chunk \(index + 1): \(error.localizedDescription)")
                // If chunk fails, include a note
                chunkSummaries.append("[Chunk \(index + 1) summary unavailable]")
            }
        }
        
        // Combine chunk summaries into final summary
        let combinedSummaries = chunkSummaries.joined(separator: "\n\n")
        
        // Create a final summary from the chunk summaries
        let finalPrompt = """
        Please provide a comprehensive summary based on these summaries of different portions of a transcription:
        
        \(combinedSummaries)
        
        Combine them into a single coherent summary covering the main topics and key points.
        """
        
        do {
            let finalResponse = try await session.respond(to: finalPrompt)
            return String(describing: finalResponse)
        } catch {
            logger.error("Failed to create final summary: \(error.localizedDescription)")
            // Return combined summaries as fallback
            return "Summary of transcription (from \(chunks.count) parts):\n\n" + combinedSummaries
        }
    }
    #endif
}

// MARK: - Supporting Types

/// Represents a chunk of transcription text with metadata
struct TranscriptionChunk {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let timestamp: Date
    let speakerLabel: String?
}

// MARK: - String Extension for Chunking

extension String {
    /// Splits a string into chunks of approximately the specified size
    func chunked(into size: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = startIndex
        
        while currentIndex < endIndex {
            let endIndex = min(index(currentIndex, offsetBy: size), self.endIndex)
            let chunk = String(self[currentIndex..<endIndex])
            chunks.append(chunk)
            currentIndex = endIndex
        }
        
        return chunks
    }
}
