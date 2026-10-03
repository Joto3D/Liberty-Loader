import Foundation

/// Editor for a bottle's `cxbottle.conf`, the INI file behind CrossOver's per-bottle settings.
/// Keys are quoted (`"WINEMSYNC" = "1"`); unrelated lines are preserved untouched.
public struct BottleConfig: Equatable {
    public static let environmentSection = "EnvironmentVariables"

    public enum GraphicsBackend: String, CaseIterable, Identifiable, Sendable {
        case d3dmetal, dxvk, wined3d
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .d3dmetal: return "D3DMetal (recommended)"
            case .dxvk: return "DXVK"
            case .wined3d: return "WineD3D (compatibility)"
            }
        }
    }

    private var lines: [String]

    public init(text: String) {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    public static func load(from url: URL) throws -> BottleConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibertyError.configNotFound(url.path) }
        return BottleConfig(text: try String(contentsOf: url, encoding: .utf8))
    }

    public var text: String { lines.joined(separator: "\n") }

    public func write(to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Typed settings

    public var graphicsBackend: GraphicsBackend? {
        get { value("CX_GRAPHICS_BACKEND", in: Self.environmentSection).flatMap { GraphicsBackend(rawValue: $0.lowercased()) } }
        set { setValue(newValue?.rawValue, for: "CX_GRAPHICS_BACKEND", in: Self.environmentSection) }
    }

    public var msyncEnabled: Bool {
        get { value("WINEMSYNC", in: Self.environmentSection) == "1" }
        set { setValue(newValue ? "1" : nil, for: "WINEMSYNC", in: Self.environmentSection) }
    }

    public var esyncEnabled: Bool {
        get { value("WINEESYNC", in: Self.environmentSection) == "1" }
        set { setValue(newValue ? "1" : nil, for: "WINEESYNC", in: Self.environmentSection) }
    }

    /// Apple's Metal performance HUD (FPS, frame time, GPU memory) on top of the game.
    public var metalHUDEnabled: Bool {
        get { value("MTL_HUD_ENABLED", in: Self.environmentSection) == "1" }
        set { setValue(newValue ? "1" : nil, for: "MTL_HUD_ENABLED", in: Self.environmentSection) }
    }

    // MARK: Generic access

    public func value(_ key: String, in section: String) -> String? {
        guard let range = sectionRange(section) else { return nil }
        for i in range {
            if let (k, v) = Self.parsePair(lines[i]), k == key { return v }
        }
        return nil
    }

    /// Sets a value, or removes the key when `value` is nil. Creates the section if needed.
    public mutating func setValue(_ value: String?, for key: String, in section: String) {
        let newLine = value.map { "\"\(key)\" = \"\($0)\"" }
        if let range = sectionRange(section) {
            if let i = range.first(where: { Self.parsePair(lines[$0])?.0 == key }) {
                if let newLine { lines[i] = newLine } else { lines.remove(at: i) }
                return
            }
            guard let newLine else { return }
            // Insert after the last non-blank line of the section.
            var insertAt = range.upperBound
            while insertAt > range.lowerBound, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            lines.insert(newLine, at: insertAt)
        } else if let newLine {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines.append("[\(section)]")
            lines.append(newLine)
        }
    }

    /// Indices of the lines belonging to `[section]`, excluding the header.
    private func sectionRange(_ section: String) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) else {
            return nil
        }
        var end = header + 1
        while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
        return (header + 1)..<end
    }

    private static func parsePair(_ line: String) -> (String, String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let unquote: (Substring) -> String = {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        let key = unquote(line[..<eq])
        guard !key.isEmpty, !key.hasPrefix(";") else { return nil }
        return (key, unquote(line[line.index(after: eq)...]))
    }
}
