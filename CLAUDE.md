# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SamScribe is a macOS transcription application that captures and transcribes audio from both the microphone and running applications (e.g., Zoom, Chrome, Teams) in real-time using FluidAudio for ASR (Automatic Speech Recognition) and speaker diarization.

## Build Commands

```bash
# Build the project
xcodebuild -project SamScribe.xcodeproj -scheme SamScribe -configuration Debug

# Build for release
xcodebuild -project SamScribe.xcodeproj -scheme SamScribe -configuration Release

# Clean build
xcodebuild clean -project SamScribe.xcodeproj -scheme SamScribe

# Open in Xcode
open SamScribe.xcodeproj
```

## Key Architecture

### Audio Pipeline Flow

1. **AudioManager** (MainActor): Orchestrates the entire audio capture and transcription pipeline
   - Manages microphone input via `AudioInput`
   - Manages per-process application audio via `ApplicationAudio`
   - Monitors audio processes via `AudioMonitor`
   - Routes audio buffers to `Transcriber`

2. **AudioInput** (Actor): Captures microphone audio using AVAudioEngine
   - Converts audio to 16kHz mono Float32 (FluidAudio format)
   - Implements mute control
   - Handles device assignment with retry logic

3. **ApplicationAudio** (Actor): Captures per-process audio using ScreenCaptureKit
   - Creates individual SCStream per audio process
   - Converts 48kHz stereo to 16kHz mono
   - Manages stream lifecycle with grace periods

4. **AudioMonitor** (@MainActor): Monitors system audio processes
   - Polls CoreAudio every 2 seconds for active audio processes
   - Implements 3-second start delay (prevents short audio spikes)
   - Implements 5-second grace period (prevents stream churn)
   - Filters for audio apps only (browsers, meeting apps, etc.)

5. **Transcriber** (Actor): Performs ASR and diarization using FluidAudio
   - Accumulates 10-second audio chunks per source
   - Processes chunks independently for each audio source (microphone vs app audio)
   - Performs ASR transcription with confidence scores
   - Performs speaker diarization and assigns speakers

### Data Flow

```
AudioInput (mic) ──┐
                   ├──> Transcriber ──> TranscriptionResult ──> TranscriptionsStore ──> SwiftData
ApplicationAudio ──┘    (10s chunks)    (with speaker info)
(per-process)
```

### Audio Format Conversions

- **Input formats**: Variable (44.1kHz-48kHz, mono/stereo)
- **Target format**: 16kHz mono Float32 (FluidAudio requirement)
- **Conversion**: AudioConverter (resampler using vDSP/Accelerate)
- **Chunk size**: 10 seconds = 160,000 samples @ 16kHz

### Permission Requirements

1. **Microphone**: Required for AudioInput (NSMicrophoneUsageDescription)
2. **Screen Recording**: Required for ScreenCaptureKit to capture app audio (NSScreenCaptureUsageDescription)
3. **Sandbox entitlements**: See SamScribe.entitlements

### Process Lifecycle Management

- **3-second start delay**: Waits 3s after detecting audio before creating SCStream (prevents spurious stream creation)
- **5-second grace period**: Waits 5s after process stops before destroying SCStream (handles temporary audio pauses)
- **Helper process mapping**: Chrome Helper → Chrome, Safari Renderer → Safari, etc.

### Key Files by Function

**Audio Capture**:
- `AudioInput.swift`: Microphone capture with AVAudioEngine
- `ApplicationAudio.swift`: Per-process app audio with ScreenCaptureKit
- `AudioMonitor.swift`: System audio process monitoring
- `AudioProcess.swift`: Audio process identification and filtering

**Transcription**:
- `Transcriber.swift`: FluidAudio integration for ASR + diarization
- `TranscriptionResult`: Data model for transcription output with speaker info

**UI & Data**:
- `TranscriptionView.swift`: Main UI entry point
- `TranscriptionsStore.swift`: Business logic layer between UI and SwiftData
- `Recording.swift`: SwiftData model for recording sessions
- `TranscriptionSegment.swift`: SwiftData model for individual transcription segments

**Utilities**:
- `Logging.swift`: Structured logging with OSLog
- `AudioConverter` (FluidAudio): Audio resampling and format conversion

## Development Notes

### FluidAudio Integration

The app depends on FluidAudio (https://github.com/FluidInference/FluidAudioSwift) which handles:
- ASR model downloading and caching
- Streaming transcription
- Speaker diarization
- Voice Activity Detection (VAD)

Note: The `Audio/` folder in the repository is a reference folder that will be deleted soon - ignore it.

### Audio Format Requirements

FluidAudio requires:
- 16kHz sample rate
- Mono (1 channel)
- Float32 PCM format
- 10-second chunks for processing

All audio inputs are converted to this format before transcription.

### ScreenCaptureKit Quirks

1. Requires at least one window to capture audio (even minimized)
2. `onScreenWindowsOnly: false` is required to capture minimized/hidden apps
3. Permission preflight: Use `CGPreflightScreenCaptureAccess()` before `CGRequestScreenCaptureAccess()`
4. Transient failures: Implement retry logic (3 attempts with 500ms backoff)

### Concurrency Model

- **AudioManager**: @MainActor (UI integration)
- **AudioInput, ApplicationAudio, Transcriber**: Actors (isolated state)
- **AudioMonitor**: @MainActor @Observable (SwiftUI integration)
- **Audio callbacks**: @Sendable closures for cross-actor communication

### SwiftData Schema

```swift
Recording {
    id: UUID
    title: String
    startDate: Date
    endDate: Date?
    segments: [TranscriptionSegment]  // cascade delete
}

TranscriptionSegment {
    id: UUID
    text: String
    timestamp: Date
    speakerID: String?
    speakerLabel: String?
    confidence: Float
    audioSource: String  // "microphone" or "appAudio"
    recording: Recording  // inverse relationship
}
```

### Common Debugging

**No transcriptions appearing**:
1. Check microphone permission granted
2. Check screen recording permission granted
3. Verify audio processes detected (check AudioMonitor logs)
4. Verify audio not silent (check amplitude logs in Transcriber)
5. Check FluidAudio model download succeeded

**SCStream creation failures**:
1. Verify screen recording permission
2. Check process has at least one window
3. Check helper process mapping worked
4. Review retry logs in ApplicationAudio

**Audio quality issues**:
1. Check input format conversion logs
2. Verify 16kHz resampling working
3. Check for buffer underruns/overruns
4. Review silence detection thresholds
