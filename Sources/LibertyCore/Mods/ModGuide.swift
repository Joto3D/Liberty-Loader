import Foundation

/// Turns Nexus Mods descriptions (BBCode mixed with HTML line breaks) into readable plain text.
public enum NexusText {
    public static func plainText(fromBBCode input: String) -> String {
        var text = input
        func replace(_ pattern: String, with template: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
        // Line breaks and entities first.
        replace(#"<br\s*/?>"#, with: "\n")
        replace(#"\r\n?"#, with: "\n")
        // Media is useless as text.
        replace(#"\[img[^\]]*\].*?\[/img\]"#, with: "")
        replace(#"\[youtube[^\]]*\].*?\[/youtube\]"#, with: "")
        // Links keep their target.
        replace(#"\[url=([^\]]+)\](.*?)\[/url\]"#, with: "$2 ($1)")
        replace(#"\[url\](.*?)\[/url\]"#, with: "$1")
        // Lists become bullets.
        replace(#"\[\*\]\s*"#, with: "\n• ")
        replace(#"\[/?list[^\]]*\]"#, with: "\n")
        // Headings and quotes get their own lines.
        replace(#"\[/?(heading|quote|spoiler|center|right|left)[^\]]*\]"#, with: "\n")
        // Everything else (b, i, u, s, size, color, font, line, …) just disappears.
        replace(#"\[/?[a-z]+(=[^\]]*)?\]"#, with: "")
        replace(#"<[^>]+>"#, with: "")
        for (entity, value) in ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&amp;": "&"] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        // Tidy whitespace.
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Finds the parts of a mod's text that explain how to use it (controls, toggles, settings).
public enum ModGuide {
    static let headingPattern = #"^\W*(how to use|how-to|usage|controls|instructions|keybind(s|ings)?|how it works|key ?bindings?|installation and usage)\b"#
    static let instructionPattern = #"\b(press(ing)?|hold(ing)?|toggle[sd]?|key ?binds?|key ?bindings?|hotkeys?|bound to|bind (it )?to|in the (game )?options|settings menu|in-game menu|default key)\b"#

    public static func instructionHighlights(in text: String, limit: Int = 8) -> [String] {
        guard let heading = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive]),
              let instruction = try? NSRegularExpression(pattern: instructionPattern, options: [.caseInsensitive]) else { return [] }
        func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
            regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }

        var highlights: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-*· "))
            guard line.count >= 6 else { return }
            if line.count > 200 { line = String(line.prefix(197)) + "…" }
            if seen.insert(line.lowercased()).inserted { highlights.append(line) }
        }

        var underHeading = 0       // lines left in the current "How to use" section
        var sectionLines = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if matches(heading, trimmed) {
                underHeading = 6
                sectionLines = 0
                // A heading like "Controls: Press V to toggle" carries the instruction itself.
                if trimmed.count > 20 { add(trimmed) }
                continue
            }
            if trimmed.isEmpty {
                // A blank line after the section's text ends the section.
                if sectionLines > 0 { underHeading = 0 }
                continue
            }
            if underHeading > 0 {
                add(trimmed)
                underHeading -= 1
                sectionLines += 1
            } else {
                // Long paragraphs: keep only the sentences that are instructions.
                for sentence in sentences(trimmed) where matches(instruction, sentence) { add(sentence) }
            }
            if highlights.count >= limit { break }
        }
        return Array(highlights.prefix(limit))
    }

    static func sentences(_ text: String) -> [String] {
        var parts: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let sub { parts.append(sub) }
        }
        return parts.isEmpty ? [text] : parts
    }
}

extension ModStore {
    /// The first readme/instructions file shipped inside the mod (up to 20 kB).
    public func readmeText(for mod: InstalledMod) -> String? {
        let root = folderURL(for: mod)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            if (name.hasPrefix("readme") || name.hasPrefix("instructions") || name.hasPrefix("how to")) && ["txt", "md", ""].contains(ext) {
                candidates.append(url)
            } else if ext == "md" {
                candidates.append(url)
            }
        }
        guard let first = candidates.sorted(by: { $0.path.count < $1.path.count }).first,
              let data = try? Data(contentsOf: first) else { return nil }
        let text = String(decoding: data.prefix(20_000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
