import Foundation

/// A log written by a mod loader inside the bottle, e.g.
/// `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/*.log` from Bingus Shared Loader.
public struct ModLogFile: Equatable, Identifiable, Sendable {
    public let url: URL
    /// Vendor folder, e.g. "CowboyBingus".
    public let source: String
    public let modified: Date

    public var id: URL { url }
}

public enum ModLogs {
    /// Newest mod loader logs in the bottle, newest first.
    public static func find(game: GamePaths, limit: Int = 5) -> [ModLogFile] {
        find(inLocalAppData: game.localAppDataDirs, limit: limit)
    }

    static func find(inLocalAppData roots: [URL], limit: Int = 5) -> [ModLogFile] {
        let fm = FileManager.default
        var found: [ModLogFile] = []
        for local in roots {
            let vendors = (try? fm.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)) ?? []
            for vendor in vendors {
                let gameDirs = ((try? fm.contentsOfDirectory(at: vendor, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent.lowercased().hasPrefix("helldivers2") }
                for gameDir in gameDirs {
                    guard let enumerator = fm.enumerator(at: gameDir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
                    for case let url as URL in enumerator {
                        if enumerator.level > 4 { enumerator.skipDescendants(); continue }
                        guard ["log", "txt"].contains(url.pathExtension.lowercased()),
                              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                              values.isRegularFile == true, let modified = values.contentModificationDate else { continue }
                        found.append(ModLogFile(url: url, source: vendor.lastPathComponent, modified: modified))
                    }
                }
            }
        }
        return Array(found.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// The last `maxLines` lines, reading at most 256 kB from the end of the file.
    public static func tail(_ url: URL, maxLines: Int = 200) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 262_144 ? size - 262_144 : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        return lines.suffix(maxLines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lines that report a problem.
    public static func problemLines(in text: String, limit: Int = 10) -> [String] {
        let pattern = #"\b(error|exception|fail(ed|ure|s)?|traceback|stack ?trace|mismatch|unsupported|not found|crash(ed)?)\b"#
        return uniqueLines(in: text, matching: pattern, limit: limit)
    }

    /// Mod identities the loader mentions, e.g. `mods/cowboybingus/mod_options_menu`.
    public static func foundMods(in text: String, limit: Int = 30) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"mods/[A-Za-z0-9_\-]+/[A-Za-z0-9_\-]+"#) else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let name = String(text[range])
            if seen.insert(name.lowercased()).inserted { result.append(name) }
            if result.count >= limit { break }
        }
        return result
    }

    /// True when a loader should have run during the last session but none of its logs changed then.
    public static func loaderDidNotRun(logs: [ModLogFile], source: String?, sessionStart: Date?, sessionEnd: Date?, lastDeploy: Date?) -> Bool {
        guard let sessionStart, let sessionEnd else { return false }
        if let lastDeploy, lastDeploy > sessionEnd { return false } // mods changed after that session
        let relevant = logs.filter { source == nil || $0.source.caseInsensitiveCompare(source!) == .orderedSame }
        // Allow some slack: logs may be flushed right after the game closes.
        return !relevant.contains { $0.modified >= sessionStart.addingTimeInterval(-60) && $0.modified <= sessionEnd.addingTimeInterval(300) }
    }

    static func uniqueLines(in text: String, matching pattern: String, limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
            let short = line.count > 240 ? String(line.prefix(237)) + "…" : line
            if seen.insert(short).inserted { result.append(short) }
            if result.count >= limit { break }
        }
        return result
    }
}
