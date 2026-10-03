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

    // Set for mods installed from Nexus Mods, used for update checks.
    public var nexusModID: Int?
    public var nexusFileID: Int?
    /// Installed version as reported by Nexus Mods.
    public var version: String?
    /// Newest version seen on Nexus Mods during the last update check.
    public var latestVersion: String?
    /// Kept at the top or bottom of the load order (from the mod's description, or set by the user).
    public var loadOrderPin: LoadOrderPin?
    /// True when the user chose the pin (or chose "Don't Pin"); auto-detection then leaves it alone.
    public var pinIsManual: Bool?

    /// Mods this one needs, as listed on Nexus Mods (nil = unknown).
    public var requirements: [NexusRequirement]?

    /// Nexus requirements that aren't installed yet.
    public func missingRequirements(installed: [InstalledMod]) -> [NexusRequirement] {
        (requirements ?? []).filter { requirement in
            guard let id = requirement.modID, !requirement.isExternal, !requirement.isModManager else { return false }
            return !installed.contains { $0.nexusModID == id }
        }
    }

    public var hasUpdate: Bool {
        guard let version, let latestVersion else { return false }
        if let installed = AppVersion(version), let latest = AppVersion(latestVersion) { return latest > installed }
        return version != latestVersion
    }
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
        // Mods installed before pins existed get them on first launch.
        if !detectPins().isEmpty { try? save() }
    }

    /// Names of mods that were pinned automatically since the app last asked.
    public private(set) var recentlyAutoPinned: [String] = []

    public func takeRecentlyAutoPinned() -> [String] {
        defer { recentlyAutoPinned = [] }
        return recentlyAutoPinned
    }

    /// Looks for load-order hints in the descriptions of mods that have no pin yet.
    /// Returns the names of newly pinned mods (not saved; callers save).
    @discardableResult
    public func detectPins() -> [String] {
        var pinned: [String] = []
        for i in mods.indices where mods[i].loadOrderPin == nil && mods[i].pinIsManual != true {
            let text = [mods[i].description, manifest(for: mods[i])?.description].compactMap { $0 }.joined(separator: "\n")
            if let pin = LoadOrderHint.detect(in: text) {
                mods[i].loadOrderPin = pin
                pinned.append(mods[i].name)
            }
        }
        recentlyAutoPinned += pinned
        return pinned
    }

    /// Pins (or unpins with nil) a mod by the user's choice.
    public func setPin(_ pin: LoadOrderPin?, for id: UUID) throws {
        guard let i = mods.firstIndex(where: { $0.id == id }) else { return }
        mods[i].loadOrderPin = pin
        mods[i].pinIsManual = true
        try save()
    }

    /// Re-runs detection (e.g. after a Nexus summary was added) and saves if anything changed.
    public func refreshPins() throws {
        if !detectPins().isEmpty { try save() }
    }

    public func folderURL(for mod: InstalledMod) -> URL {
        modsDirectory.appendingPathComponent(mod.folderName)
    }

    public func manifest(for mod: InstalledMod) -> ModManifest? {
        try? ModManifest.load(from: folderURL(for: mod).appendingPathComponent("manifest.json"))
    }

    // MARK: Install / remove

    /// Installs a mod. With `replacing`, the existing mod's files are swapped for the new download
    /// while its place in the load order, enabled state and chosen variant are kept.
    @discardableResult
    public func install(from source: URL, replacing existingID: UUID? = nil) throws -> InstalledMod {
        let fm = FileManager.default
        let id = UUID()
        let staging = rootURL.appendingPathComponent("staging-\(id.uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try ModArchive.extract(source, to: staging)

        let contentRoot = ModArchive.contentRoot(of: staging)
        guard !PatchSet.collect(in: [contentRoot]).isEmpty else {
            throw ModArchive.containsWindowsProgram(contentRoot) ? LibertyError.windowsProgram : LibertyError.noPatchFiles
        }

        let folder = modsDirectory.appendingPathComponent(id.uuidString)
        try fm.moveItem(at: contentRoot, to: folder)

        let manifest = try? ModManifest.load(from: folder.appendingPathComponent("manifest.json"))
        let fallbackName = source.deletingPathExtension().lastPathComponent

        if let existingID, let index = mods.firstIndex(where: { $0.id == existingID }) {
            var mod = mods[index]
            try? fm.removeItem(at: folderURL(for: mod))
            mod.folderName = id.uuidString
            mod.name = manifest?.name ?? mod.name
            mod.description = manifest?.description ?? mod.description
            if let options = manifest?.options, let selected = mod.selectedOption, selected >= options.count {
                mod.selectedOption = 0
                mod.selectedSubOption = 0
            }
            mods[index] = mod
            detectPins()
            try save()
            LibertyLog.shared.info("Updated mod \(mod.name) from \(source.lastPathComponent)")
            return mod
        }

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
        detectPins()
        try save()
        LibertyLog.shared.info("Installed mod \(mod.name) from \(source.lastPathComponent)")
        return mod
    }

    /// Manifest icon if the mod ships one, otherwise a `preview.*` image saved at install time.
    public func previewImageURL(for mod: InstalledMod) -> URL? {
        let folder = folderURL(for: mod)
        let fm = FileManager.default
        if let icon = manifest(for: mod)?.iconPath, !icon.isEmpty {
            let url = folder.appendingPathComponent(icon.replacingOccurrences(of: "\\", with: "/"))
            if fm.fileExists(atPath: url.path) { return url }
        }
        for ext in ["png", "jpg", "jpeg", "webp", "gif"] {
            let url = folder.appendingPathComponent("preview.\(ext)")
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
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

    /// Replaces the whole list (same mods, new order/settings).
    public func replaceAll(_ newMods: [InstalledMod]) throws {
        mods = newMods
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
        mods = LoadOrderHint.normalized(mods)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(mods).write(to: indexURL, options: .atomic)
    }
}
