import Foundation

/// Line-preserving editor for Wine registry files (`user.reg`, `system.reg`) inside a bottle.
///
/// Wine rewrites these files when the bottle shuts down, so edits must only be made while
/// nothing is running in the bottle.
public struct WineRegistryFile: Equatable {
    private var lines: [String]

    public init(text: String) {
        lines = text.components(separatedBy: "\n")
    }

    public static func load(from url: URL) throws -> WineRegistryFile {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibertyError.configNotFound(url.path) }
        return WineRegistryFile(text: try String(contentsOf: url, encoding: .utf8))
    }

    public var text: String { lines.joined(separator: "\n") }

    public func write(to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// - Parameter key: registry path with single backslashes, e.g. `Software\Wine\Mac Driver`.
    public func string(_ name: String, in key: String) -> String? {
        guard let range = sectionRange(key) else { return nil }
        let prefix = "\"\(name)\"="
        for i in range where lines[i].hasPrefix(prefix) {
            return String(lines[i].dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    public mutating func setString(_ value: String?, for name: String, in key: String, now: Date = Date()) {
        let prefix = "\"\(name)\"="
        let newLine = value.map { "\(prefix)\"\($0)\"" }
        if let range = sectionRange(key) {
            if let i = range.first(where: { lines[$0].hasPrefix(prefix) }) {
                if let newLine { lines[i] = newLine } else { lines.remove(at: i) }
                return
            }
            guard let newLine else { return }
            var insertAt = range.upperBound
            while insertAt > range.lowerBound, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            lines.insert(newLine, at: insertAt)
        } else if let newLine {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            lines += ["", "[\(Self.fileKey(key))] \(Int(now.timeIntervalSince1970))", newLine, ""]
        }
    }

    /// Registry files escape backslashes: `Software\\Wine\\Mac Driver`.
    static func fileKey(_ key: String) -> String {
        key.replacingOccurrences(of: "\\", with: "\\\\")
    }

    private func sectionRange(_ key: String) -> Range<Int>? {
        let header = "[\(Self.fileKey(key).lowercased())]"
        guard let start = lines.firstIndex(where: { $0.lowercased().hasPrefix(header) }) else { return nil }
        var end = start + 1
        while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
        return (start + 1)..<end
    }
}

extension GamePaths {
    public var userRegistryURL: URL { bottleURL.appendingPathComponent("user.reg") }
}

/// CrossOver's "High Resolution Mode": render at full Retina resolution. Looks sharper but costs a lot of FPS.
public enum RetinaMode {
    public static let key = "Software\\Wine\\Mac Driver"
    public static let name = "RetinaMode"

    public static func isEnabled(in registry: WineRegistryFile) -> Bool {
        registry.string(name, in: key)?.lowercased().hasPrefix("y") == true
    }

    public static func set(_ enabled: Bool, in registry: inout WineRegistryFile) {
        registry.setString(enabled ? "y" : "n", for: name, in: key)
    }
}
