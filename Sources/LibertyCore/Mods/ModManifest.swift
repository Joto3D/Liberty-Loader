import Foundation

/// `manifest.json` as written by the popular HD2 Mod Manager, so existing Nexus mods install unchanged.
///
/// Legacy (no `Version`): `Options` is a list of folder names.
/// Version 1: `Options` is a list of objects with `Name`, `Description`, `Include` and `SubOptions`.
public struct ModManifest: Equatable, Sendable {
    public struct SubOption: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var include: [String]
    }

    public struct Option: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var include: [String]
        public var subOptions: [SubOption]
    }

    public var version: Int?
    public var guid: String?
    public var name: String
    public var description: String?
    public var iconPath: String?
    public var options: [Option]

    public static func load(from url: URL) throws -> ModManifest {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> ModManifest {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options: [Option] = (json["Options"] as? [Any] ?? []).compactMap { raw in
            if let folder = raw as? String {
                return Option(name: folder, description: nil, include: [folder], subOptions: [])
            }
            guard let dict = raw as? [String: Any], let name = dict["Name"] as? String else { return nil }
            let subOptions: [SubOption] = (dict["SubOptions"] as? [[String: Any]] ?? []).compactMap { sub in
                guard let subName = sub["Name"] as? String else { return nil }
                return SubOption(name: subName, description: sub["Description"] as? String, include: sub["Include"] as? [String] ?? [])
            }
            return Option(name: name, description: dict["Description"] as? String, include: dict["Include"] as? [String] ?? [], subOptions: subOptions)
        }
        return ModManifest(
            version: json["Version"] as? Int,
            guid: json["Guid"] as? String,
            name: json["Name"] as? String ?? "Unnamed Mod",
            description: json["Description"] as? String,
            iconPath: json["IconPath"] as? String,
            options: options
        )
    }

    /// Folders (relative to the mod root) whose patch files should be deployed for a selection.
    ///
    /// Kept for callers that still think in single selections; forwards to the
    /// set-based version below.
    /// Note this clamps an out-of-range index to the last option, which the
    /// set-based version deliberately does not do — there, an index that no
    /// longer exists is dropped. Callers of the old API relied on clamping.
    public func includedFolders(option: Int?, subOption: Int?) -> [String] {
        guard !options.isEmpty else { return [""] }
        let index = min(max(option ?? 0, 0), options.count - 1)
        return includedFolders(options: [index], subOptions: subOption.map { [index: $0] } ?? [:])
    }

    /// Folders for any number of chosen options.
    ///
    /// Top-level options are usually independent — a mod offering twelve
    /// weapons ships twelve folders that share no files, so there is no reason
    /// to make the user pick one. Sub-options are the opposite: they are
    /// variants of a single option ("Quiet Ping" or "Loud Ping" for the same
    /// autocannon), so exactly one applies per chosen option, which is why
    /// `subOptions` is keyed by option index rather than being a set.
    ///
    /// An empty `options` means "nothing chosen yet" and falls back to the
    /// first option, matching the old single-selection behaviour for mods
    /// installed before multi-selection existed.
    public func includedFolders(options chosen: Set<Int>, subOptions: [Int: Int]) -> [String] {
        guard !options.isEmpty else { return [""] }
        let valid = chosen.filter { $0 >= 0 && $0 < options.count }.sorted()
        let indices = valid.isEmpty ? [0] : valid
        var folders: [String] = []
        for index in indices {
            let option = options[index]
            folders += option.include
            if !option.subOptions.isEmpty {
                let raw = subOptions[index] ?? 0
                let sub = option.subOptions[min(max(raw, 0), option.subOptions.count - 1)]
                folders += sub.include
            }
        }
        // Two options can legitimately name the same folder; deploy it once.
        var seen = Set<String>()
        return folders.filter { seen.insert($0).inserted }
    }

    /// Whether these options can be combined, or must behave as a radio group.
    ///
    /// Options that would deploy the same folder cannot stack — one would
    /// simply win — so such a mod keeps single-selection. This is decided from
    /// the manifest rather than assumed, because the format has no flag for it.
    public var optionsAreCombinable: Bool {
        guard options.count > 1 else { return false }
        var seen = Set<String>()
        for option in options {
            for folder in option.include where !seen.insert(folder).inserted { return false }
        }
        return true
    }
}
