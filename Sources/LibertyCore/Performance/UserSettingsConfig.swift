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
        let name = key.split(separator: ".").last.map(String.init) ?? key
        lines[entry.line] = "\(indent)\(name) = \(value)"
        entries[i].value = value
        return true
    }

    /// Applies many values; returns the keys that were not present in the file.
    public mutating func apply(_ values: [String: String]) -> [String] {
        var missing: [String] = []
        for key in values.keys.sorted() {
            if set(key, to: values[key]!) { continue }
            // Presets name the leaf (`shadows`); the game may keep it in a block (`render_settings.shadows`).
            let nested = entries.filter { $0.key.hasSuffix(".\(key)") }
            if nested.count == 1 {
                set(nested[0].key, to: values[key]!)
            } else {
                missing.append(key)
            }
        }
        return missing
    }

    public func write(to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads single-line `key = value` entries at the top level and inside named object blocks
    /// such as `render_settings = { … }`; nested keys are dotted (`render_settings.shadows`).
    /// Arrays and anonymous blocks are skipped.
    private static func parseEntries(_ lines: [String]) -> [Entry] {
        var stack: [(name: String, isArray: Bool)] = []
        var pendingName: String?
        var result: [Entry] = []
        for (n, line) in lines.enumerated() {
            var opens: [Character] = []
            var closes = 0
            var inString = false
            for ch in line {
                if ch == "\"" { inString.toggle() }
                if inString { continue }
                if ch == "{" || ch == "[" { opens.append(ch) }
                if ch == "}" || ch == "]" {
                    if opens.isEmpty { closes += 1 } else { opens.removeLast() }
                }
            }
            let pair = keyValue(line)
            for _ in 0..<closes where !stack.isEmpty { stack.removeLast() }
            if let first = opens.first {
                // `name = {` or a lone `{` after `name =`.
                let name = pair.map { $0.value.first == first ? $0.key : "" } ?? pendingName ?? ""
                stack.append((name, first == "["))
                for extra in opens.dropFirst() { stack.append(("", extra == "[")) }
                pendingName = nil
                continue
            }
            if let pair, pair.value.isEmpty {
                pendingName = pair.key
                continue
            }
            pendingName = nil
            guard closes == 0, let pair,
                  !stack.contains(where: { $0.isArray || $0.name.isEmpty }) else { continue }
            let key = (stack.map(\.name) + [pair.key]).joined(separator: ".")
            result.append(Entry(key: key, value: pair.value, line: n))
        }
        return result
    }

    private static func keyValue(_ line: String) -> (key: String, value: String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.hasPrefix("//"),
              key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (key, value)
    }
}
