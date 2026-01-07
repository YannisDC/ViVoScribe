import Foundation
import OSLog
import AudioToolbox

@MainActor
@Observable
final class AudioMonitor {
    private let logger = Logging(name: "AudioMonitor")

    // State
    private(set) var activeAudioProcesses: [AudioProcess] = []
    private(set) var isMonitoring = false

    // Grace period for process lifecycle
    private var gracePeriodTasks: [pid_t: Task<Void, Never>] = [:]
    private let gracePeriodDuration: TimeInterval = 5.0

    // Start delay to prevent short audio spikes from creating streams
    private var pendingStartTasks: [pid_t: Task<Void, Never>] = [:]
    private let startDelayDuration: TimeInterval = 3.0

    // Monitoring
    private var monitoringTask: Task<Void, Never>?
    private let checkInterval: TimeInterval = 2.0 // Check every 2 seconds

    // Callbacks for process lifecycle
    var onProcessStarted: (@Sendable (AudioProcess) async -> Void)?
    var onProcessStopped: (@Sendable (pid_t) async -> Void)?

    init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        logger.info("Starting audio process monitoring")
        isMonitoring = true

        monitoringTask = Task {
            while !Task.isCancelled && isMonitoring {
                await checkAudioProcesses()

                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        logger.info("Stopping audio process monitoring")
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func checkAudioProcesses() async {
        do {
            // Get all audio processes
            let objectIDs = try AudioObjectID.readProcessList()

            // Convert to AudioProcess and filter for audio apps with active audio
            let audioProcesses = objectIDs.compactMap { objectID -> AudioProcess? in
                guard let process = try? AudioProcess(objectID: objectID) else { return nil }
                return process.isAudioApp && process.audioActive ? process : nil
            }

            // Check if processes changed
            let previousPIDs = Set(activeAudioProcesses.map { $0.id })
            let currentPIDs = Set(audioProcesses.map { $0.id })

            if previousPIDs != currentPIDs {
                logger.info("🎧 APPLICATIONS - Audio processes changed")
                logger.info("   📱 Now listening to: \(audioProcesses.map { "\($0.name) (PID: \($0.id))" }.joined(separator: ", "))")
                if audioProcesses.isEmpty {
                    logger.info("   ❌ No audio applications with active audio detected")
                }

                // Detect new processes
                let newPIDs = currentPIDs.subtracting(previousPIDs)
                for pid in newPIDs {
                    if let process = audioProcesses.first(where: { $0.id == pid }) {
                        // Cancel grace period if process reappeared
                        if let graceTask = gracePeriodTasks[pid] {
                            graceTask.cancel()
                            gracePeriodTasks[pid] = nil
                            logger.info("   ✅ Process \(process.name) (PID: \(pid)) reappeared - grace period cancelled")
                        }

                        // Cancel any existing pending start task
                        pendingStartTasks[pid]?.cancel()

                        // Start 3-second delay before creating stream
                        logger.info("   🕐 Process started: \(process.name) (PID: \(pid)) - waiting 3s to confirm sustained audio")

                        let startTask = Task { [weak self] in
                            do {
                                try await Task.sleep(for: .seconds(3.0))

                                // 3 seconds passed - notify that stream should be created
                                self?.logger.info("   ✅ 3-second delay complete for \(process.name) (PID: \(pid)) - creating stream")
                                await self?.onProcessStarted?(process)
                                self?.pendingStartTasks[pid] = nil
                            } catch {
                                // Task was cancelled - audio stopped before 3 seconds
                                self?.logger.info("   ❌ Process \(process.name) (PID: \(pid)) audio stopped before 3s - stream not created")
                            }
                        }

                        pendingStartTasks[pid] = startTask
                    }
                }

                // Detect stopped processes - start grace period
                let stoppedPIDs = previousPIDs.subtracting(currentPIDs)
                for pid in stoppedPIDs {
                    // Cancel pending start task if audio stopped before 3 seconds
                    if let pendingTask = pendingStartTasks[pid] {
                        pendingTask.cancel()
                        pendingStartTasks[pid] = nil
                        logger.info("   ⏸️ Process PID \(pid) stopped before 3s delay - pending stream creation cancelled")
                        continue // Don't start grace period since stream was never created
                    }

                    logger.info("   ⏸️ Process stopped: PID \(pid) - starting 5s grace period")

                    // Cancel existing grace task if any
                    gracePeriodTasks[pid]?.cancel()

                    // Start 5-second grace period
                    let graceTask = Task { [weak self] in
                        do {
                            try await Task.sleep(for: .seconds(5.0))

                            // Grace period expired - notify that process is truly gone
                            self?.logger.info("   ❌ Grace period expired for PID \(pid) - removing process")
                            await self?.onProcessStopped?(pid)
                            self?.gracePeriodTasks[pid] = nil

                        } catch is CancellationError {
                            // Process restarted - grace period was cancelled (logged above)
                        } catch {
                            // Other errors (shouldn't happen with Task.sleep)
                            self?.logger.error("   ⚠️ Grace period error for PID \(pid): \(error)")
                        }
                    }

                    gracePeriodTasks[pid] = graceTask
                }

                activeAudioProcesses = audioProcesses
            }

        } catch {
            logger.error("❌ Failed to check audio processes: \(error)")
        }
    }

    // Public interface
    func getActiveAudioProcesses() -> [AudioProcess] {
        activeAudioProcesses
    }

    var hasActiveAudio: Bool {
        !activeAudioProcesses.isEmpty
    }
}

// Audio device helpers
extension AudioDeviceID {
    static func readDefaultSystemInputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceID
        )

        guard status == noErr else { throw AudioError.propertyNotFound }
        return deviceID
    }
}