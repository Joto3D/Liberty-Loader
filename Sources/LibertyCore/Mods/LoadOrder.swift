import Foundation

/// Where a mod must sit in the load order. Lower in the list wins, so shared loaders that
/// other mods build on ("place this loader LAST") are pinned to the bottom.
public enum LoadOrderPin: String, Codable, Sendable {
    case top, bottom
}

public enum LoadOrderHint {
    private static let bottomPatterns = [
        #"\bplace (this|the|it)( \w+)? last\b"#,
        #"\bload (this|the|it)( \w+)? last\b"#,
        #"bottom of (the|your) (mod )?list"#,
        #"\bmust be (loaded |placed )?last\b"#,
        #"keep (it |this )?at the bottom"#,
        #"\b(load|place) order:? last\b"#,
    ]
    private static let topPatterns = [
        #"\bplace (this|the|it)( \w+)? first\b"#,
        #"\bload(ed)? (this|the|it)( \w+)? first\b"#,
        #"top of (the|your) (mod )?list"#,
        #"\bmust be (loaded |placed )?first\b"#,
    ]

    /// Reads a mod's own description. Bottom wins when both appear (e.g. "LAST …, or FIRST if
    /// first-mod priority is enabled"), matching Liberty Loader's "lower wins" order.
    public static func detect(in text: String) -> LoadOrderPin? {
        let lowered = text.lowercased()
        func matches(_ patterns: [String]) -> Bool {
            patterns.contains { lowered.range(of: $0, options: .regularExpression) != nil }
        }
        if matches(bottomPatterns) { return .bottom }
        if matches(topPatterns) { return .top }
        return nil
    }

    /// Stable reorder: top pins, then unpinned mods, then bottom pins.
    public static func normalized(_ mods: [InstalledMod]) -> [InstalledMod] {
        mods.filter { $0.loadOrderPin == .top }
            + mods.filter { $0.loadOrderPin == nil }
            + mods.filter { $0.loadOrderPin == .bottom }
    }
}
