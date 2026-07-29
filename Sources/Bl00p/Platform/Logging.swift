import Foundation

#if os(macOS)
import os
#endif

/// Minimal logging facade.
///
/// `os.Logger` is an Apple-platform module with no swift-corelibs counterpart,
/// so the Linux build writes to standard error instead.
struct Bl00pLogger: Sendable {
    #if os(macOS)
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
    #else
    private let label: String

    init(subsystem: String, category: String) {
        label = "\(subsystem) \(category)"
    }

    func error(_ message: String) {
        FileHandle.standardError.write(
            Data("[\(label)] error: \(message)\n".utf8)
        )
    }

    func info(_ message: String) {
        FileHandle.standardError.write(
            Data("[\(label)] info: \(message)\n".utf8)
        )
    }
    #endif
}
