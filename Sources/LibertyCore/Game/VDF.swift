import Foundation

/// Minimal reader for Valve's KeyValues text files (libraryfolders.vdf, appmanifest_*.acf).
/// We only ever need the values of simple `"key" "value"` pairs.
public enum VDF {
    public static func values(forKey key: String, in text: String) -> [String] {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\"\(escapedKey)\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\"", options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r]).replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    public static func value(forKey key: String, in text: String) -> String? {
        values(forKey: key, in: text).first
    }
}
