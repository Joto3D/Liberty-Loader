import Foundation

/// Line-preserving editor for Arrowhead's `user_settings.config` (Stingray SJSON: `key = value`).
///
/// Only top-level single-line `key = value` entries are editable. Nested blocks, comments and
/// formatting are kept byte-for-byte, so the game never sees a file it didn't write itself
/// except for the values the user changed.
public struct UserSettingsConfig: Equatable {
    public struct Entry: Equatable, Identifiable {
        public var id: String { key }
        public let key: String
        public var value: String
        let line: Int
    }

    private var lines: [String]
    public private(set) var entries: [Entry]

    public init(text: String) {
        lines = text.components(separatedBy: "\n")
        entries = Self.parseEntries(lines)
    }

    public static func load(from url: URL) throws -> UserSettingsConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibertyError.configNotFound(url.path) }
        return UserSettingsConfig(text: try String(contentsOf: url, encoding: .utf8))
    }

    public var text: String { lines.joined(separator: "\n") }

    public func value(for key: String) -> String? {
        entries.first { $0.key == key }?.value
    }

    /// Sets an existing key. Returns false when the key isn't in the file: unknown keys are never
    /// added, because the game may not understand them.
    @discardableResult
    public mutating func set(_ key: String, to value: String) -> Bool {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return false }
        let entry = entries[i]
        let indent = lines[entry.line].prefix { $0 == " " || $0 == "\t" }
        lines[entry.line] = "\(indent)\(key) = \(value)"
        entries[i].value = value
        return true
    }

    /// Applies many values; returns the keys that were not present in the file.
    public mutating func apply(_ values: [String: String]) -> [String] {
        var missing: [String] = []
        for key in values.keys.sorted() {
            if !set(key, to: values[key]!) { missing.append(key) }
        }
        return missing
    }

    public func write(to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func parseEntries(_ lines: [String]) -> [Entry] {
        var depth = 0
        var result: [Entry] = []
        var inString = false
        for (n, line) in lines.enumerated() {
            let startDepth = depth
            for ch in line {
                if ch == "\"" { inString.toggle() }
                if inString { continue }
                if ch == "{" || ch == "[" { depth += 1 }
                if ch == "}" || ch == "]" { depth = max(0, depth - 1) }
            }
            guard startDepth == 0, depth == 0,
                  let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty, !key.hasPrefix("//"),
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            result.append(Entry(key: key, value: value, line: n))
        }
        return result
    }
}
