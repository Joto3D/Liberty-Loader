import Foundation

public struct InstalledMod: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var selectedOption: Int?
    public var selectedSubOption: Int?
    public var installedAt: Date
    /// Mod contents, relative to the store's mods directory.
    public var folderName: String
}

/// A mod with its selected option resolved to concrete patch files.
public struct ResolvedMod: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let patchSets: [PatchSet]
}

/// Mod library kept in `~/Library/Application Support/LibertyLoader`. Mods live here and are only
/// copied into the game's data folder by `PatchDeployer`, so the game folder can always be restored.
public final class ModStore {
    public let rootURL: URL
    public var modsDirectory: URL { rootURL.appendingPathComponent("mods") }
    var indexURL: URL { rootURL.appendingPathComponent("mods.json") }

    /// Mods in load order: later entries win when two mods patch the same file.
    public private(set) var mods: [InstalledMod] = []

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LibertyLoader")
    }

    public init(rootURL: URL = ModStore.defaultRoot) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            mods = try decoder.decode([InstalledMod].self, from: data)
        }
    }

    public func folderURL(for mod: InstalledMod) -> URL {
        modsDirectory.appendingPathComponent(mod.folderName)
    }

    public func manifest(for mod: InstalledMod) -> ModManifest? {
        try? ModManifest.load(from: folderURL(for: mod).appendingPathComponent("manifest.json"))
    }

    // MARK: Install / remove

    @discardableResult
    public func install(from source: URL) throws -> InstalledMod {
        let fm = FileManager.default
        let id = UUID()
        let staging = rootURL.appendingPathComponent("staging-\(id.uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try ModArchive.extract(source, to: staging)

        let contentRoot = ModArchive.contentRoot(of: staging)
        guard !PatchSet.collect(in: [contentRoot]).isEmpty else { throw LibertyError.noPatchFiles }

        let folder = modsDirectory.appendingPathComponent(id.uuidString)
        try fm.moveItem(at: contentRoot, to: folder)

        let manifest = try? ModManifest.load(from: folder.appendingPathComponent("manifest.json"))
        let fallbackName = source.deletingPathExtension().lastPathComponent
        let mod = InstalledMod(
            id: id,
            name: manifest?.name ?? fallbackName,
            description: manifest?.description,
            enabled: true,
            selectedOption: manifest?.options.isEmpty == false ? 0 : nil,
            selectedSubOption: manifest?.options.first?.subOptions.isEmpty == false ? 0 : nil,
            installedAt: Date(),
            folderName: id.uuidString
        )
        mods.append(mod)
        try save()
        LibertyLog.shared.info("Installed mod \(mod.name) from \(source.lastPathComponent)")
        return mod
    }

    public func uninstall(_ id: UUID) throws {
        guard let mod = mods.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: folderURL(for: mod))
        mods.removeAll { $0.id == id }
        try save()
        LibertyLog.shared.info("Uninstalled mod \(mod.name)")
    }

    // MARK: Editing

    public func update(_ mod: InstalledMod) throws {
        guard let i = mods.firstIndex(where: { $0.id == mod.id }) else { return }
        mods[i] = mod
        try save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        // Same semantics as SwiftUI's `onMove`, implemented without SwiftUI so it works in tests.
        let moving = source.sorted().map { mods[$0] }
        var remaining = mods
        for i in source.sorted(by: >) { remaining.remove(at: i) }
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        mods = remaining
        try save()
    }

    public func setAllEnabled(_ enabled: Bool) throws {
        for i in mods.indices { mods[i].enabled = enabled }
        try save()
    }

    // MARK: Resolution

    public func resolvedEnabledMods() -> [ResolvedMod] {
        mods.filter(\.enabled).map(resolve)
    }

    public func resolve(_ mod: InstalledMod) -> ResolvedMod {
        let root = folderURL(for: mod)
        let directories: [URL]
        if let manifest = manifest(for: mod), !manifest.options.isEmpty {
            directories = manifest.includedFolders(option: mod.selectedOption, subOption: mod.selectedSubOption)
                .map { $0.isEmpty ? root : root.appendingPathComponent($0.replacingOccurrences(of: "\\", with: "/")) }
        } else {
            directories = [root]
        }
        return ResolvedMod(id: mod.id, name: mod.name, patchSets: PatchSet.collect(in: directories))
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(mods).write(to: indexURL, options: .atomic)
    }
}
