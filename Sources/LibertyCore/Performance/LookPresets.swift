import Foundation

/// How the finished frame is graded, sharpened and blurred.
///
/// Deliberately not a `PerformancePreset`. A quality preset decides how much
/// work the GPU does; a look decides what is done with the result. They are
/// chosen independently, so picking a look must not undo the quality level the
/// user settled on — which is exactly what reusing `PerformancePreset` would
/// have done, since applying one writes its whole settings dictionary.
///
/// Every key here is one that really exists in `user_settings.config`. The game
/// has no film grain, vignette, chromatic aberration or tone-mapping setting,
/// so a look cannot offer those, however common they are in ReShade presets.
/// `UserSettingsConfig.apply` never invents a key, so anything the user's file
/// lacks is reported rather than written.
public struct LookPreset: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let settings: [String: String]

    /// Film-like: graded, bloomed, with depth of field and a little motion blur,
    /// and sharpening pulled back, since film is soft rather than crisp.
    public static let cinematic = LookPreset(
        id: "cinematic",
        name: "Cinematic",
        summary: "Film-like. Colour grading, bloom, depth of field and a little motion blur, with sharpening eased off. Costs some frames.",
        settings: [
            "color_grading_enabled": "true",
            "bloom_enabled": "true",
            "dof_enabled": "true",
            "lens_quality_enabled": "true",
            "heathaze_enabled": "true",
            "motion_blur_enabled": "true",
            "motion_blur_amount_multiplier": "0.35",
            "sharpening_enabled": "true",
            "sharpening_amount": "0.4",
        ]
    )

    /// The opposite trade: everything that softens or smears the image off, so
    /// targets stay readable. Cheaper than Cinematic, not more expensive.
    public static let crisp = LookPreset(
        id: "crisp",
        name: "Crisp",
        summary: "Clean and readable. Blur, depth of field and heat haze off, sharpening up. Slightly faster than Cinematic.",
        settings: [
            "color_grading_enabled": "true",
            "bloom_enabled": "false",
            "dof_enabled": "false",
            "lens_quality_enabled": "false",
            "heathaze_enabled": "false",
            "motion_blur_enabled": "false",
            "motion_blur_amount_multiplier": "0",
            "sharpening_enabled": "true",
            "sharpening_amount": "1",
            "vrs_sharpening_enabled": "true",
            "vrs_sharpening_strength": "0.65",
        ]
    )

    public static let all = [cinematic, crisp]

    /// The keys any look writes. Used to show what the current file holds and
    /// to tell whether a look is already applied.
    public static var allKeys: Set<String> {
        all.reduce(into: Set<String>()) { $0.formUnion($1.settings.keys) }
    }

    /// Whether this look is what the config currently holds.
    ///
    /// Values are compared as numbers where both sides parse as numbers, so
    /// `0.4` and `0.40000001` — which is what the game writes back after
    /// reading a float — count as the same setting.
    public func matches(_ config: UserSettingsConfig) -> Bool {
        for (key, wanted) in settings {
            guard let actual = config.value(for: key) ?? config.nestedValue(for: key) else { return false }
            if actual == wanted { continue }
            guard let a = Double(actual), let b = Double(wanted), abs(a - b) < 0.001 else { return false }
        }
        return true
    }
}

extension UserSettingsConfig {
    /// The value of a key the game keeps inside a block, named by its leaf
    /// (`sharpening_amount` for `render_settings.sharpening_amount`), matching
    /// how `apply` resolves preset keys. Nil when the leaf is ambiguous.
    public func nestedValue(for key: String) -> String? {
        let nested = entries.filter { $0.key.hasSuffix(".\(key)") }
        return nested.count == 1 ? nested[0].value : nil
    }
}
