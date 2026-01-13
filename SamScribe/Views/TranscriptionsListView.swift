import SwiftUI

struct TranscriptionsListView: View {
    @Bindable var store: TranscriptionsStore
    @State private var editingRecordingID: UUID?
    @State private var newTitle = ""
    
    var body: some View {
        List(selection: $store.selectedRecordingId) {
            if !todayRecordings.isEmpty {
                Section("Today") {
                    ForEach(todayRecordings) { recording in
                        RecordingListRow(
                            recording: recording,
                            store: store,
                            isEditing: editingRecordingID == recording.id,
                            newTitle: $newTitle,
                            onStartEdit: { editingRecordingID = recording.id },
                            onSaveEdit: { title in
                                store.renameRecording(id: recording.id, newTitle: title)
                                editingRecordingID = nil
                            },
                            onCancelEdit: { editingRecordingID = nil }
                        )
                        .tag(recording.id)
                    }
                }
            }
            
            if !yesterdayRecordings.isEmpty {
                Section("Yesterday") {
                    ForEach(yesterdayRecordings) { recording in
                        RecordingListRow(
                            recording: recording,
                            store: store,
                            isEditing: editingRecordingID == recording.id,
                            newTitle: $newTitle,
                            onStartEdit: { editingRecordingID = recording.id },
                            onSaveEdit: { title in
                                store.renameRecording(id: recording.id, newTitle: title)
                                editingRecordingID = nil
                            },
                            onCancelEdit: { editingRecordingID = nil }
                        )
                        .tag(recording.id)
                    }
                }
            }
            
            if !thisWeekRecordings.isEmpty {
                Section("This Week") {
                    ForEach(thisWeekRecordings) { recording in
                        RecordingListRow(
                            recording: recording,
                            store: store,
                            isEditing: editingRecordingID == recording.id,
                            newTitle: $newTitle,
                            onStartEdit: { editingRecordingID = recording.id },
                            onSaveEdit: { title in
                                store.renameRecording(id: recording.id, newTitle: title)
                                editingRecordingID = nil
                            },
                            onCancelEdit: { editingRecordingID = nil }
                        )
                        .tag(recording.id)
                    }
                }
            }
            
            if !thisMonthRecordings.isEmpty {
                Section("This Month") {
                    ForEach(thisMonthRecordings) { recording in
                        RecordingListRow(
                            recording: recording,
                            store: store,
                            isEditing: editingRecordingID == recording.id,
                            newTitle: $newTitle,
                            onStartEdit: { editingRecordingID = recording.id },
                            onSaveEdit: { title in
                                store.renameRecording(id: recording.id, newTitle: title)
                                editingRecordingID = nil
                            },
                            onCancelEdit: { editingRecordingID = nil }
                        )
                        .tag(recording.id)
                    }
                }
            }
            
            if !olderRecordings.isEmpty {
                Section("Older") {
                    ForEach(olderRecordings) { recording in
                        RecordingListRow(
                            recording: recording,
                            store: store,
                            isEditing: editingRecordingID == recording.id,
                            newTitle: $newTitle,
                            onStartEdit: { editingRecordingID = recording.id },
                            onSaveEdit: { title in
                                store.renameRecording(id: recording.id, newTitle: title)
                                editingRecordingID = nil
                            },
                            onCancelEdit: { editingRecordingID = nil }
                        )
                        .tag(recording.id)
                    }
                }
            }
            
            if store.recordings.isEmpty {
                Section {
                    Text("No transcriptions yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Transcriptions")
        .onChange(of: store.selectedRecordingId) { oldValue, newValue in
            if let id = newValue {
                store.setSelectedRecording(id)
            }
        }
    }
    
    // MARK: - Date Filtering
    
    private var todayRecordings: [RecordingViewModel] {
        store.recordings.filter { Calendar.current.isDateInToday($0.startDate) }
    }
    
    private var yesterdayRecordings: [RecordingViewModel] {
        store.recordings.filter { Calendar.current.isDateInYesterday($0.startDate) }
    }
    
    private var thisWeekRecordings: [RecordingViewModel] {
        let now = Date()
        let startOfWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        
        return store.recordings.filter { recording in
            !Calendar.current.isDateInToday(recording.startDate) &&
            !Calendar.current.isDateInYesterday(recording.startDate) &&
            recording.startDate >= startOfWeek
        }
    }
    
    private var thisMonthRecordings: [RecordingViewModel] {
        let now = Date()
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
        let startOfWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        
        return store.recordings.filter { recording in
            !Calendar.current.isDateInToday(recording.startDate) &&
            !Calendar.current.isDateInYesterday(recording.startDate) &&
            recording.startDate < startOfWeek &&
            recording.startDate >= startOfMonth
        }
    }
    
    private var olderRecordings: [RecordingViewModel] {
        let now = Date()
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
        
        return store.recordings.filter { recording in
            recording.startDate < startOfMonth
        }
    }
}

struct RecordingListRow: View {
    let recording: RecordingViewModel
    @Bindable var store: TranscriptionsStore
    let isEditing: Bool
    @Binding var newTitle: String
    let onStartEdit: () -> Void
    let onSaveEdit: (String) -> Void
    let onCancelEdit: () -> Void
    @State private var elapsedTime: TimeInterval = 0
    
    private var isActiveRecording: Bool {
        recording.id == store.currentRecording?.id
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Recording name", text: $newTitle, onCommit: {
                        onSaveEdit(newTitle)
                    })
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        newTitle = recording.title
                    }
                } else {
                    Text(recording.title)
                        .font(.headline)
                }
                
                HStack(spacing: 8) {
                    Text(recording.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(displayDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if recording.segmentCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(recording.segmentCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .contextMenu {
            Button {
                onStartEdit()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                Task {
                    try? await store.deleteRecording(recording.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onAppear {
            if isActiveRecording {
                startTimer()
            }
        }
        .onChange(of: isActiveRecording) { oldValue, newValue in
            if newValue {
                startTimer()
            }
        }
    }
    
    private var displayDuration: String {
        let duration = isActiveRecording ? elapsedTime : recording.duration
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if isActiveRecording {
                elapsedTime = Date().timeIntervalSince(recording.startDate)
            } else {
                timer.invalidate()
            }
        }
    }
}
