import SwiftUI

struct SidebarView: View {
    @Bindable var store: TranscriptionsStore

    var body: some View {
        List(selection: $store.selectedRecordingId) {
            if !todayRecordings.isEmpty {
                Section("Today") {
                    ForEach(todayRecordings) { recording in
                        RecordingListRow(recording: recording, store: store)
                            .tag(recording.id)
                    }
                }
            }

            if !yesterdayRecordings.isEmpty {
                Section("Yesterday") {
                    ForEach(yesterdayRecordings) { recording in
                        RecordingListRow(recording: recording, store: store)
                            .tag(recording.id)
                    }
                }
            }

            if !thisWeekRecordings.isEmpty {
                Section("This Week") {
                    ForEach(thisWeekRecordings) { recording in
                        RecordingListRow(recording: recording, store: store)
                            .tag(recording.id)
                    }
                }
            }

            if !thisMonthRecordings.isEmpty {
                Section("This Month") {
                    ForEach(thisMonthRecordings) { recording in
                        RecordingListRow(recording: recording, store: store)
                            .tag(recording.id)
                    }
                }
            }

            if !olderRecordings.isEmpty {
                Section("Older") {
                    ForEach(olderRecordings) { recording in
                        RecordingListRow(recording: recording, store: store)
                            .tag(recording.id)
                    }
                }
            }
        }
        .navigationTitle("Recordings")
        .listStyle(.sidebar)
        .accentColor(.accentColor)
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
    @State private var isRenaming = false
    @State private var newTitle = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if isRenaming {
                    TextField("Recording name", text: $newTitle, onCommit: {
                        saveRename()
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

                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .contextMenu {
            Button {
                isRenaming = true
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
    }

    private func saveRename() {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            isRenaming = false
            return
        }
        store.renameRecording(id: recording.id, newTitle: newTitle)
        isRenaming = false
    }
}
