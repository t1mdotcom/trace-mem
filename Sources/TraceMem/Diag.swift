import Foundation
import os

/// Unified log + plain file (~/Library/Logs/trace-mem.log) so users can attach it to bug reports.
enum Diag {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/trace-mem.log")
    private static let osLog = Logger(subsystem: "dev.theinemann.trace-mem", category: "diag")
    private static let queue = DispatchQueue(label: "trace-mem.diag")
    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f }()

    static func log(_ message: String, level: OSLogType = .default) {
        osLog.log(level: level, "\(message, privacy: .public)")
        let line = "\(stamp.string(from: Date())) [\(level == .error ? "ERROR" : "INFO")] \(message)\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            } else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    static func error(_ message: String) { log(message, level: .error) }
}
