import Foundation
import OSLog

final class Logging: Sendable {
    #if DEBUG
        nonisolated public let logLevel: LogLevel = .debug
    #else
        nonisolated public let logLevel: LogLevel = .info
    #endif

    private let logger: Logger
    private let serviceName: String

    init(name: String) {
        let uuid = UUID().uuidString
        logger = Logger()
        serviceName = name
    }

    @frozen
    public enum LogLevel: Int {
        case debug = 1
        case info = 2
        case error = 3
        case none = 4

        func shouldLog(level: LogLevel) -> Bool {
            return self.rawValue <= level.rawValue
        }
    }

    func debug(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let itemsCopy = items.map { item in
            if let str = item as? String {
                return str
            }
            return String(describing: item)
        }

        if logLevel.shouldLog(level: .debug) {
            log(items: itemsCopy, separator: separator, terminator: terminator, type: .debug)
        }
    }

    func info(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let itemsCopy = items.map { item in
            if let str = item as? String {
                return str
            }
            return String(describing: item)
        }

        if logLevel.shouldLog(level: .info) {
            log(items: itemsCopy, separator: separator, terminator: terminator, type: .info)
        }
    }

    func error(
        _ items: Any..., separator: String = " ", terminator: String = "\n", error: Error? = nil
    ) {
        let itemsCopy = items.map { item in
            if let str = item as? String {
                return str
            }
            return String(describing: item)
        }
        let errorCopy = error.map { String(describing: $0) }

        if logLevel.shouldLog(level: .error) {
            log(
                items: itemsCopy,
                separator: separator,
                terminator: terminator,
                type: .error,
                errorDescription: errorCopy
            )
        }
    }

    private func log(
        items: [String],
        separator: String = " ",
        terminator: String = "\n",
        type: OSLogType,
        errorDescription: String? = nil
    ) {
        let message = items.joined(separator: separator)
        let timestamp = Date().ISO8601Format()

        var logPrefix =
            switch type {
            case .debug: "[🔍 DEBUG]"
            case .info: "[ℹ️ INFO]"
            case .error: "[❌ ERROR]"
            default: "[📝 NOTICE]"
            }

        logPrefix = "[\(timestamp)]:[\(serviceName)]:\(logPrefix)"

        // Log to system logger
        switch type {
        case .debug:
            logger.debug("\(logPrefix): \(message)")
        case .info:
            logger.info("\(logPrefix): \(message)")
        case .error:
            logger.error("\(logPrefix): \(message)")
        default:
            logger.notice("\(logPrefix): \(message)")
        }

        if type == .debug {
            return
        }
    }

    private struct TimeoutError: Error {}
}
