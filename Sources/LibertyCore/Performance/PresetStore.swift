import Foundation

extension PerformancePreset {
    public var isBuiltIn: Bool { Self.all.contains { $0.id == id } }

    /// Captures the user's current game and bottle settings as a reusable preset.
    public static func custom(name: String, config: UserSettingsConfig, bottle: BottleConfig?) -> PerformancePreset {
        var preset = PerformancePreset(
            id: UUID().uuidString,
            name: name,
            summary: "Your saved settings.",
            gameSettings: Dictionary(config.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last }),
            graphicsBackend: bottle?.graphicsBackend ?? .d3dmetal,
            msync: bottle?.msyncEnabled ?? true
        )
        preset.esync = bottle?.esyncEnabled
        preset.metalHUD = bottle?.metalHUDEnabled
        return preset
    }
}

/// User-made presets, saved next to the mod library.
public final class PresetStore {
    let fileURL: URL
    public private(set) var custom: [PerformancePreset] = []

    public init(rootURL: URL = ModStore.defaultRoot) {
        fileURL = rootURL.appendingPathComponent("custom-presets.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([PerformancePreset].self, from: data) {
            custom = decoded
        }
    }

    public var all: [PerformancePreset] { PerformancePreset.all + custom }

    public func add(_ preset: PerformancePreset) throws {
        custom.removeAll { $0.name == preset.name }
        custom.append(preset)
        try write()
    }

    public func delete(id: String) throws {
        custom.removeAll { $0.id == id }
        try write()
    }

    private func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(custom).write(to: fileURL, options: .atomic)
    }
}
