import Foundation

/// A saved mod setup ("Cosmetics only", "Everything"): which mods are on, their order and variants.
public struct ModProfile: Codable, Identifiable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var modID: UUID
        public var enabled: Bool
        public var selectedOption: Int?
        public var selectedSubOption: Int?
    }

    public var id: UUID
    public var name: String
    public var entries: [Entry]
}

public final class ModProfileStore {
    let fileURL: URL
    public private(set) var profiles: [ModProfile] = []

    public init(rootURL: URL = ModStore.defaultRoot) {
        fileURL = rootURL.appendingPathComponent("profiles.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ModProfile].self, from: data) {
            profiles = decoded
        }
    }

    /// Saves the current mod setup under `name`, replacing a profile with the same name.
    @discardableResult
    public func save(name: String, from mods: [InstalledMod]) throws -> ModProfile {
        let entries = mods.map {
            ModProfile.Entry(modID: $0.id, enabled: $0.enabled, selectedOption: $0.selectedOption, selectedSubOption: $0.selectedSubOption)
        }
        let profile: ModProfile
        if let i = profiles.firstIndex(where: { $0.name == name }) {
            profiles[i].entries = entries
            profile = profiles[i]
        } else {
            profile = ModProfile(id: UUID(), name: name, entries: entries)
            profiles.append(profile)
        }
        try write()
        return profile
    }

    public func delete(_ id: UUID) throws {
        profiles.removeAll { $0.id == id }
        try write()
    }

    private func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(profiles).write(to: fileURL, options: .atomic)
    }
}

extension ModStore {
    /// Applies a profile: its mods take its order and settings; mods installed after the
    /// profile was saved are kept at the end, disabled.
    public func apply(_ profile: ModProfile) throws {
        var byID = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, $0) })
        var ordered: [InstalledMod] = []
        for entry in profile.entries {
            guard var mod = byID.removeValue(forKey: entry.modID) else { continue }
            mod.enabled = entry.enabled
            mod.selectedOption = entry.selectedOption
            mod.selectedSubOption = entry.selectedSubOption
            ordered.append(mod)
        }
        let leftovers = mods.filter { byID[$0.id] != nil }.map { mod -> InstalledMod in
            var m = mod
            m.enabled = false
            return m
        }
        try replaceAll(ordered + leftovers)
    }
}
