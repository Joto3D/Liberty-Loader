import Foundation

/// Tiny append-only logger shared by the app and the core library.
public final class LibertyLog: @unchecked Sendable {
    public static let shared = LibertyLog()

    private let queue = DispatchQueue(label: "LibertyLoader.log")
    public private(set) var fileURL: URL?

    public func configure(fileURL: URL) {
        queue.sync {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.fileURL = fileURL
        }
    }

    public func info(_ message: String) { write("INFO", message) }
    public func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            guard let url = self.fileURL, let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
