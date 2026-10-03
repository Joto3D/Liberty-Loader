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
    public func includedFolders(option: Int?, subOption: Int?) -> [String] {
        guard !options.isEmpty else { return [""] }
        let chosen = options[min(max(option ?? 0, 0), options.count - 1)]
        var folders = chosen.include
        if !chosen.subOptions.isEmpty {
            let sub = chosen.subOptions[min(max(subOption ?? 0, 0), chosen.subOptions.count - 1)]
            folders += sub.include
        }
        return folders
    }
}
