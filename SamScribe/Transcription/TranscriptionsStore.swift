import Combine
import SwiftData
import SwiftUI

@Observable
@MainActor
final class TranscriptionsStore {
    private let logger = Logging(name: "TranscriptionsStore")
    private var modelContext: ModelContext?
    private var speakerManager: SpeakerManager?  // NEW: Add SpeakerManager

    // Cached data
    var recordings: [RecordingViewModel] = []
    var selectedRecordingId: UUID?
    var selectedRecording: RecordingViewModel?
    private var isRefreshing = false
    private var lastFetchTime: Date = .distantPast
    private var debounceInterval: TimeInterval = 0.5

    // Auto-save timer
    private var autoSaveTimer: Timer?
    var currentRecording: Recording?

    init() {}

    func initialize(with context: ModelContext) {
        self.modelContext = context
        self.speakerManager = SpeakerManager(modelContext: context)  // NEW: Initialize SpeakerManager
        Task { @MainActor in
            await refreshData()
        }
    }

    // MARK: - Data Fetching

    func refreshData() async {
        guard let context = modelContext else { return }

        guard !isRefreshing else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFetchTime) > debounceInterval else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        logger.info("Refreshing recordings")
        lastFetchTime = Date()

        do {
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\Recording.startDate, order: .reverse)]
            )

            let fetchedRecordings = try context.fetch(descriptor)
            recordings = fetchedRecordings.map { RecordingViewModel(from: $0) }
        } catch {
            logger.error("Failed to fetch recordings: \(error.localizedDescription)", error: error)
        }
    }

    // MARK: - Recording Management

    func createNewRecording() {
        guard let modelContext = modelContext else {
            logger.error("ModelContext not initialized")
            return
        }

        let recording = Recording(
            title: "New Recording",
            startDate: Date()
        )

        modelContext.insert(recording)
        currentRecording = recording
        selectedRecordingId = recording.id

        // Add to cached array
        recordings.insert(RecordingViewModel(from: recording), at: 0)

        try? modelContext.save()
        logger.info("Created new recording: \(recording.id)")

        // Start auto-save timer when recording begins
        startAutoSaveTimer()
    }

    func stopCurrentRecording() {
        guard let recording = currentRecording else { return }

        // Stop the auto-save timer
        stopAutoSaveTimer()

        recording.endDate = Date()

        // Final save to ensure all segments are persisted
        try? modelContext?.save()

        currentRecording = nil

        logger.info("Stopped recording: \(recording.id)")

        // Refresh to update view model
        Task { await refreshData() }
    }

    // MARK: - Transcription Integration

    func addTranscriptionSegment(_ result: TranscriptionResult) {
        guard let recording = currentRecording,
              let speakerManager = speakerManager else {
            logger.error("No current recording or speaker manager")
            return
        }

        // NEW: Speaker matching logic
        var assignedSpeaker: Speaker? = nil
        if let embedding = result.embedding {
            assignedSpeaker = speakerManager.assignSpeaker(
                embedding: embedding,
                segmentDuration: Float(result.endTime - result.startTime)
            )
        }

        // Create segment with embedding data
        let segment = TranscriptionSegment(from: result)
        segment.recording = recording
        segment.speaker = assignedSpeaker  // NEW: Link to speaker
        recording.segments.append(segment)

        // Update UI in real-time if this is the selected recording
        if selectedRecordingId == recording.id {
            refreshSelectedRecording()
        }

        // Note: Actual save happens on 30s timer
    }

    private func refreshSelectedRecording() {
        guard let id = selectedRecordingId,
              let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<Recording>(
                predicate: #Predicate<Recording> { $0.id == id }
            )

            if let recording = try context.fetch(descriptor).first {
                selectedRecording = RecordingViewModel(from: recording, includeSegments: true)
            }
        } catch {
            logger.error("Failed to refresh selected recording: \(error.localizedDescription)")
        }
    }

    // MARK: - Auto-Save Timer

    private func startAutoSaveTimer() {
        // Prevent multiple timers from running
        guard autoSaveTimer == nil else {
            logger.info("Auto-save timer already running")
            return
        }

        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveCurrentRecording()
            }
        }
        logger.info("Started 30-second auto-save timer")
    }

    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        // Final save on stop
        saveCurrentRecording()
        logger.info("Stopped auto-save timer")
    }

    private func saveCurrentRecording() {
        guard let context = modelContext else { return }

        do {
            try context.save()
            logger.info("Auto-saved current recording")
        } catch {
            logger.error("Failed to save recording: \(error.localizedDescription)", error: error)
        }
    }

    // MARK: - Selection

    func setSelectedRecording(_ id: UUID) {
        selectedRecordingId = id

        // Fetch full recording with segments if needed
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<Recording>(
                predicate: #Predicate<Recording> { $0.id == id }
            )

            if let recording = try context.fetch(descriptor).first {
                selectedRecording = RecordingViewModel(from: recording, includeSegments: true)
            }
        } catch {
            logger.error("Failed to fetch recording: \(error.localizedDescription)")
        }
    }

    func clearSelectedRecording() {
        selectedRecordingId = nil
        selectedRecording = nil
    }

    // MARK: - Deletion

    func deleteRecording(_ id: UUID) async throws {
        guard let mainContext = modelContext else {
            throw NSError(domain: "TranscriptionsStore", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "ModelContext not initialized"])
        }

        // Update cached data first
        recordings.removeAll { $0.id == id }

        if selectedRecordingId == id {
            clearSelectedRecording()
        }

        // Create separate context for deletion (thread safety)
        let container = mainContext.container
        let deleteContext = ModelContext(container)

        do {
            let descriptor = FetchDescriptor<Recording>(
                predicate: #Predicate<Recording> { $0.id == id }
            )

            guard let recordingToDelete = try deleteContext.fetch(descriptor).first else {
                logger.error("Recording \(id) not found")
                return
            }

            logger.info("Deleting recording: \(recordingToDelete.id)")
            deleteContext.delete(recordingToDelete)
            try deleteContext.save()

            logger.info("Successfully deleted recording \(id)")
        } catch {
            logger.error("Failed to delete recording: \(error.localizedDescription)", error: error)
            throw error
        }
    }

    // MARK: - Edit Operations

    func renameRecording(id: UUID, newTitle: String) {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<Recording>(
                predicate: #Predicate<Recording> { $0.id == id }
            )

            if let recording = try context.fetch(descriptor).first {
                recording.title = newTitle
                try context.save()
                logger.info("Renamed recording: \(id) to '\(newTitle)'")

                // Update cached recordings array
                if let index = recordings.firstIndex(where: { $0.id == id }) {
                    recordings[index] = RecordingViewModel(from: recording)
                }

                // Update selected recording if it's the one being renamed
                if selectedRecordingId == id {
                    selectedRecording = RecordingViewModel(from: recording, includeSegments: true)
                }
            }
        } catch {
            logger.error("Failed to rename recording: \(error.localizedDescription)")
        }
    }

    func updateSegmentText(_ segmentId: UUID, newText: String) {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<TranscriptionSegment>(
                predicate: #Predicate<TranscriptionSegment> { $0.id == segmentId }
            )

            if let segment = try context.fetch(descriptor).first {
                segment.text = newText
                try context.save()
                logger.info("Updated segment text: \(segmentId)")

                // Refresh UI to show updated text
                refreshSelectedRecording()
            }
        } catch {
            logger.error("Failed to update segment: \(error.localizedDescription)")
        }
    }

    func deleteSegment(_ segmentId: UUID) {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<TranscriptionSegment>(
                predicate: #Predicate<TranscriptionSegment> { $0.id == segmentId }
            )

            if let segment = try context.fetch(descriptor).first {
                context.delete(segment)
                try context.save()
                logger.info("Deleted segment: \(segmentId)")

                // Refresh UI to remove deleted segment
                refreshSelectedRecording()
            }
        } catch {
            logger.error("Failed to delete segment: \(error.localizedDescription)")
        }
    }

    // NEW: Speaker rename method
    func renameSpeaker(_ speaker: Speaker, newName: String) {
        guard let speakerManager = speakerManager else { return }
        speakerManager.renameSpeaker(speaker, newName: newName)
        refreshSelectedRecording()  // Refresh to show updated names
    }

    // MARK: - Audio File Import
    
    func importAudioFile(url: URL) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "TranscriptionsStore", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "ModelContext not initialized"])
        }
        
        logger.info("Importing audio file: \(url.lastPathComponent)")
        
        // Create new recording for the imported file
        // Store the URL as a bookmark for security-scoped access
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let bookmarkString = bookmarkData?.base64EncodedString()
        
        let recording = Recording(
            title: url.deletingPathExtension().lastPathComponent,
            startDate: Date(),
            audioFileURL: bookmarkString
        )
        
        modelContext.insert(recording)
        currentRecording = recording
        selectedRecordingId = recording.id
        
        // Add to cached array
        recordings.insert(RecordingViewModel(from: recording), at: 0)
        
        try? modelContext.save()
        logger.info("Created recording for import: \(recording.id)")
        
        // Initialize transcriber and process file
        let transcriber = Transcriber()
        let audioProcessor = AudioFileProcessor()
        
        do {
            // Initialize transcriber
            try await transcriber.initialize()
            
            // Set up transcription result handler
            try await transcriber.startTranscription { [weak self] result in
                Task { @MainActor in
                    self?.addTranscriptionSegment(result)
                }
            }
            
            // Process the audio file
            try await audioProcessor.processAudioFile(
                url: url,
                transcriber: transcriber,
                recordingStartDate: recording.startDate,
                onProgress: { [weak self] progress in
                    // Progress updates can be handled here if needed
                    self?.logger.info("Import progress: \(Int(progress * 100))%")
                },
                onComplete: { [weak self] in
                    // File processing complete
                    self?.logger.info("Audio file import complete")
                }
            )
            
            // Mark recording as complete
            recording.endDate = Date()
            try? modelContext.save()
            
            // Refresh to update view model
            await refreshData()
            
            logger.info("Successfully imported audio file: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to import audio file: \(error.localizedDescription)", error: error)
            // Clean up on error
            if let recording = currentRecording {
                modelContext.delete(recording)
                try? modelContext.save()
                currentRecording = nil
            }
            throw error
        }
    }

}
