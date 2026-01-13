import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var store: TranscriptionsStore
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedSection: SidebarSection
    @State private var speakers: [Speaker] = []
    @State private var blockCounts: [UUID: Int] = [:]

    var body: some View {
        List(selection: $selectedSection) {
            // Navigation Section
            Section("Navigation") {
                SidebarItem(
                    icon: "house.fill",
                    title: "Home",
                    section: .home,
                    selectedSection: $selectedSection
                )
                .tag(SidebarSection.home)
                
                SidebarItem(
                    icon: "circle.fill",
                    title: "Queue",
                    section: .queue,
                    selectedSection: $selectedSection
                )
                .tag(SidebarSection.queue)
            }
            
            // History Section
            Section("History") {
                SidebarItem(
                    icon: "list.bullet",
                    title: "Transcriptions",
                    section: .transcriptions,
                    selectedSection: $selectedSection
                )
                .tag(SidebarSection.transcriptions)
                
                SidebarItem(
                    icon: "calendar",
                    title: "Meetings",
                    section: .meetings,
                    selectedSection: $selectedSection
                )
                .tag(SidebarSection.meetings)
                
                SidebarItem(
                    icon: "mic.fill",
                    title: "AI Dictations",
                    section: .aiDictations,
                    selectedSection: $selectedSection
                )
                .tag(SidebarSection.aiDictations)
            }
            
            // People Section
            if !speakers.isEmpty {
                Section("People") {
                    ForEach(speakers) { speaker in
                        HStack(spacing: 8) {
                            // Speaker initial circle
                            Circle()
                                .fill(colorForSpeaker(speaker))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(initialsForSpeaker(speaker))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                            
                            Text(speaker.displayName)
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Text("\(blockCounts[speaker.id] ?? 0)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(SidebarSection.speaker(speaker.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteSpeaker(speaker)
                            } label: {
                                Label("Delete Speaker", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SamScribe")
        .onAppear {
            loadSpeakers()
            countBlocksPerSpeaker()
        }
        .onChange(of: selectedSection) { oldValue, newValue in
            handleSectionSelection(newValue)
        }
    }
    
    private func loadSpeakers() {
        do {
            let descriptor = FetchDescriptor<Speaker>(
                sortBy: [SortDescriptor(\Speaker.createdAt, order: .reverse)]
            )
            speakers = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch speakers: \(error)")
        }
    }
    
    private func countBlocksPerSpeaker() {
        do {
            // Get all recordings
            let recordingsDescriptor = FetchDescriptor<Recording>()
            let recordings = try modelContext.fetch(recordingsDescriptor)
            
            // Count blocks per speaker
            var counts: [UUID: Int] = [:]
            
            for recording in recordings {
                // Get all segments for this recording, sorted by timestamp
                let segments = recording.segments
                    .sorted(by: { $0.timestamp < $1.timestamp })
                    .map { TranscriptionSegmentViewModel(from: $0) }
                
                // Group segments into blocks (same logic as RecordingDetailView)
                let blocks = groupSegmentsIntoBlocks(segments)
                
                // Count blocks per speaker
                for block in blocks {
                    if let speakerId = block.speaker?.id {
                        counts[speakerId, default: 0] += 1
                    }
                }
            }
            
            blockCounts = counts
        } catch {
            print("Failed to count blocks per speaker: \(error)")
        }
    }
    
    private func groupSegmentsIntoBlocks(_ segments: [TranscriptionSegmentViewModel]) -> [TranscriptionBlock] {
        guard !segments.isEmpty else { return [] }
        
        var blocks: [TranscriptionBlock] = []
        var currentBlockSegments: [TranscriptionSegmentViewModel] = []
        
        for segment in segments {
            if currentBlockSegments.isEmpty {
                // Start a new block
                currentBlockSegments.append(segment)
            } else {
                // Check if this segment can be grouped with the current block
                let lastSegment = currentBlockSegments.last!
                let canGroup = (lastSegment.speaker?.id == segment.speaker?.id) && 
                               (lastSegment.speaker != nil || segment.speaker == nil)
                
                if canGroup {
                    // Add to current block
                    currentBlockSegments.append(segment)
                } else {
                    // Finalize current block and start a new one
                    blocks.append(TranscriptionBlock(segments: currentBlockSegments))
                    currentBlockSegments = [segment]
                }
            }
        }
        
        // Don't forget the last block
        if !currentBlockSegments.isEmpty {
            blocks.append(TranscriptionBlock(segments: currentBlockSegments))
        }
        
        return blocks
    }
    
    private func colorForSpeaker(_ speaker: Speaker) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .yellow, .cyan, .mint, .indigo]
        let index = abs(speaker.id.hashValue) % colors.count
        return colors[index]
    }
    
    private func initialsForSpeaker(_ speaker: Speaker) -> String {
        let name = speaker.displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2)).uppercased()
        }
        return "??"
    }
    
    private func handleSectionSelection(_ section: SidebarSection) {
        switch section {
        case .home:
            store.clearSelectedRecording()
        case .transcriptions:
            // Show transcriptions list - handled by detail view
            store.clearSelectedRecording()
        case .meetings, .aiDictations, .queue:
            // Could filter recordings by type
            store.clearSelectedRecording()
            break
        case .speaker(let id):
            // Could filter by speaker
            store.clearSelectedRecording()
            break
        }
    }
    
    private func deleteSpeaker(_ speaker: Speaker) {
        store.deleteSpeaker(speaker)
        // Reload speakers after deletion
        loadSpeakers()
        // Recalculate block counts
        countBlocksPerSpeaker()
    }
}

enum SidebarSection: Hashable, Identifiable {
    case home
    case queue
    case transcriptions
    case meetings
    case aiDictations
    case speaker(UUID)
    
    var id: String {
        switch self {
        case .home: return "home"
        case .queue: return "queue"
        case .transcriptions: return "transcriptions"
        case .meetings: return "meetings"
        case .aiDictations: return "aiDictations"
        case .speaker(let id): return "speaker-\(id.uuidString)"
        }
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let section: SidebarSection
    @Binding var selectedSection: SidebarSection
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(title)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSection = section
        }
    }
}
