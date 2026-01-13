import SwiftUI
import AVFoundation
import Combine

@MainActor
final class AudioMiniPlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false
    @Published var currentPlayingSegmentID: UUID?
    
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegate?
    private var audioFileURL: URL?
    private var updateTimer: Timer?
    private var recordingStartDate: Date?
    
    func loadAudio(url: URL, recordingStartDate: Date? = nil) {
        audioFileURL = url
        self.recordingStartDate = recordingStartDate
        isLoading = true
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = AudioPlayerDelegate { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.currentTime = 0
                    self?.currentPlayingSegmentID = nil
                }
            }
            player.delegate = delegate
            
            self.audioPlayer = player
            self.audioPlayerDelegate = delegate
            self.duration = player.duration
            self.isLoading = false
            
            player.prepareToPlay()
        } catch {
            print("Failed to load audio: \(error)")
            isLoading = false
        }
    }
    
    func playFromSegment(
        startTime: TimeInterval,
        endTime: TimeInterval,
        segmentTimestamp: Date,
        recordingStartDate: Date,
        segmentID: UUID
    ) {
        // Calculate absolute time in the recording
        let timeSinceRecordingStart = segmentTimestamp.timeIntervalSince(recordingStartDate)
        let absoluteStartTime = max(0, timeSinceRecordingStart) + startTime
        
        // Seek to the start time and play
        seek(to: absoluteStartTime)
        currentPlayingSegmentID = segmentID
        play()
    }
    
    func play() {
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = min(max(0, time), duration)
        currentTime = audioPlayer?.currentTime ?? 0
    }
    
    func skipForward(seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = min(player.currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func skipBackward(seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = max(player.currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    private func startTimer() {
        stopTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                
                // Check if playback finished
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.currentTime = 0
                    self.currentPlayingSegmentID = nil
                }
            }
        }
    }
    
    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    nonisolated deinit {
        // Timer cleanup happens automatically when object is deallocated
    }
}

// Helper class for AVAudioPlayerDelegate
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

struct AudioMiniPlayer: View {
    @ObservedObject var viewModel: AudioMiniPlayerViewModel
    let audioFileURL: URL?
    let recordingStartDate: Date?
    
    var body: some View {
        if let url = audioFileURL {
            VStack(spacing: 0) {
                // Progress bar at top
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        
                        // Progress track
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0), height: 4)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let percentage = value.location.x / geometry.size.width
                                let newTime = TimeInterval(percentage) * viewModel.duration
                                viewModel.seek(to: newTime)
                            }
                    )
                }
                .frame(height: 4)
                
                // Controls - centered horizontally
                HStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        // Rewind 15 seconds
                        Button(action: {
                            viewModel.skipBackward(seconds: 15)
                        }) {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Rewind 15 seconds")
                        
                        // Rewind 5 seconds
                        Button(action: {
                            viewModel.skipBackward(seconds: 5)
                        }) {
                            Image(systemName: "gobackward.5")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Rewind 5 seconds")
                        
                        // Play/Pause
                        Button(action: {
                            viewModel.togglePlayPause()
                        }) {
                            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.isPlaying ? "Pause" : "Play")
                        
                        // Forward 5 seconds
                        Button(action: {
                            viewModel.skipForward(seconds: 5)
                        }) {
                            Image(systemName: "goforward.5")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Forward 5 seconds")
                        
                        // Forward 15 seconds
                        Button(action: {
                            viewModel.skipForward(seconds: 15)
                        }) {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Forward 15 seconds")
                    }
                    
                    Spacer()
                    
                    // Time display
                    Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.controlBackgroundColor))
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .onAppear {
                viewModel.loadAudio(url: url, recordingStartDate: recordingStartDate)
            }
            .onChange(of: audioFileURL) { oldValue, newValue in
                if let url = newValue {
                    viewModel.stop()
                    viewModel.loadAudio(url: url, recordingStartDate: recordingStartDate)
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
