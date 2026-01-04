import Foundation
import AudioToolbox

struct AudioProcess: Identifiable, Hashable, Sendable {
    let id: pid_t
    let name: String
    let bundleID: String?
    let audioActive: Bool
    let objectID: AudioObjectID

    init(objectID: AudioObjectID) throws {
        let pid: pid_t = try objectID.read(kAudioProcessPropertyPID, defaultValue: -1)

        self.id = pid
        self.objectID = objectID
        self.audioActive = objectID.readProcessIsRunning()

        // Get process info
        if let info = Self.processInfo(for: pid) {
            self.name = info.name
            self.bundleID = info.bundleID
        } else {
            self.name = "Unknown (\(pid))"
            self.bundleID = nil
        }
    }

    // Check if this is an audio app
    var isAudioApp: Bool {
        let audioAppIdentifiers = [
            "chrome", "opera", "zoom", "slack", "browser helper",
            "safari", "edge", "firefox", "mozilla", "teams", "webex",
            "whatsapp", "messenger", "telegram", "signal", "viber",
            "kik", "skype", "discord", "wechat", "aircall", "facetime",
            "vivaldi", "zen", "arc", "dia", "brave", "orion", "iina",
            "comet", "chromium", "tor browser", "waterfox", "librewolf",
            "basilisk", "perplexity", "thebrowser", "ai.perplexity",
            "company.thebrowser", "kagimacOS", "kagi", "youtube", "google"
        ]

        let name = self.name.lowercased()
        let bundleID = self.bundleID?.lowercased() ?? ""

        return audioAppIdentifiers.contains { identifier in
            name.contains(identifier) || bundleID.contains(identifier)
        }
    }

    // Check if this is a helper/background process
    // Helper processes should be filtered out - main app captures their audio
    nonisolated var isHelperProcess: Bool {
        let helperKeywords = ["helper", "renderer", "gpu", "plugin"]
        let name = self.name.lowercased()
        return helperKeywords.contains { name.contains($0) }
    }

    private static func processInfo(for pid: pid_t) -> (name: String, bundleID: String?)? {
        let nameBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
        let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))

        defer {
            nameBuffer.deallocate()
            pathBuffer.deallocate()
        }

        let nameLength = proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))

        guard nameLength > 0 else { return nil }

        let name = String(cString: nameBuffer)

        // Try to get bundle ID from path
        var bundleID: String?
        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            bundleID = extractBundleID(from: path)
        }

        return (name: name, bundleID: bundleID)
    }

    private static func extractBundleID(from path: String) -> String? {
        // Simple extraction - look for .app bundles
        if path.contains(".app/") {
            let components = path.components(separatedBy: "/")
            for component in components {
                if component.hasSuffix(".app") {
                    return component.replacingOccurrences(of: ".app", with: "")
                }
            }
        }
        return nil
    }
}

extension AudioObjectID {
    func read<T>(_ property: AudioObjectPropertySelector, defaultValue: T) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = defaultValue

        let sizeStatus = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else { throw AudioError.propertyNotFound }

        let dataStatus = withUnsafeMutablePointer(to: &result) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, pointer)
        }
        guard dataStatus == noErr else { throw AudioError.propertyNotFound }

        return result
    }

    func readProcessIsRunning() -> Bool {
        do {
            let running: UInt32 = try read(kAudioProcessPropertyIsRunning, defaultValue: 0)
            return running != 0
        } catch {
            return false
        }
    }

    static func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard sizeStatus == noErr else { throw AudioError.propertyNotFound }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = Array<AudioObjectID>(repeating: 0, count: count)

        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &objectIDs
        )
        guard dataStatus == noErr else { throw AudioError.propertyNotFound }

        return objectIDs
    }
}

enum AudioError: Error {
    case propertyNotFound
}