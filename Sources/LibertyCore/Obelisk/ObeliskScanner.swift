import Foundation

/// Finds Helldivers 2 installs managed by Obelisk.
///
/// Obelisk's layout, unlike a CrossOver bottle, keeps the game and the Wine
/// prefix in separate trees under its application-support directory:
///
///     com.zagrios.obelisk/
///       Games/Steam/steam-<appID>-windows/          <- bin/, data/
///       Prefixes/steam-<appID>-windows-linux/prefix <- drive_c/
///
/// The suffixes are not fixed: the platform tail (`-windows`, `-windows-linux`)
/// depends on how Obelisk installed the title, so discovery matches on the
/// `steam-<appID>` stem rather than assuming a whole directory name.
public struct ObeliskScanner: Sendable {
    /// `~/Library/Application Support/com.zagrios.obelisk`
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.zagrios.obelisk")
    }

    public let root: URL

    public init(root: URL = ObeliskScanner.defaultRoot) {
        self.root = root
    }

    /// Every Obelisk install of the given app, newest-looking first.
    ///
    /// An install only counts when its game directory actually exists; a prefix
    /// without a game, or an entry left behind in Obelisk's index after an
    /// uninstall, must not be returned.
    public func installs(appID: String = GamePaths.steamAppID) -> [GamePaths] {
        let stem = "steam-\(appID)-"
        let prefixes = prefixRoots(stem: stem)
        guard let prefixRoot = prefixes.first else { return [] }

        var seen = Set<String>()
        var result: [GamePaths] = []
        for gameRoot in gameRoots(appID: appID, stem: stem) {
            let key = gameRoot.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted, Self.looksInstalled(gameRoot) else { continue }
            result.append(GamePaths(obeliskGameRoot: gameRoot, prefixRoot: prefixRoot))
        }
        return result
    }

    // MARK: - Game directories

    /// Index entries first (authoritative), then a directory scan as fallback.
    private func gameRoots(appID: String, stem: String) -> [URL] {
        var roots = indexedDirectories(appID: appID)
        let steamGames = root.appendingPathComponent("Games/Steam")
        roots += Self.subdirectories(of: steamGames, withPrefix: stem)
        return roots
    }

    /// Reads every `steam-installations-<steamid>.json` (one per Steam account).
    /// Each is a JSON array; `.incomplete.json` siblings hold in-progress
    /// installs and are ignored. Anything unparseable is skipped.
    private func indexedDirectories(appID: String) -> [URL] {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        var urls: [URL] = []
        for name in names where name.hasPrefix("steam-installations-")
            && name.hasSuffix(".json") && !name.hasSuffix(".incomplete.json") {
            let file = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file),
                  let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
            for entry in entries {
                // appId is a number in the file, but tolerate a string.
                let id = (entry["appId"] as? NSNumber)?.stringValue ?? (entry["appId"] as? String)
                guard id == appID, let dir = entry["directory"] as? String, !dir.isEmpty else { continue }
                urls.append(URL(fileURLWithPath: dir, isDirectory: true))
            }
        }
        return urls
    }

    private static func looksInstalled(_ gameRoot: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: gameRoot.path, isDirectory: &isDir), isDir.boolValue else { return false }
        return fm.fileExists(atPath: gameRoot.appendingPathComponent("bin/helldivers2.exe").path)
            || fm.fileExists(atPath: gameRoot.appendingPathComponent("data").path)
    }

    // MARK: - Prefixes

    /// Prefix roots (folders containing `drive_c`), best first. Obelisk can leave
    /// several `steam-<appID>-*` folders behind; only those with a `prefix`
    /// child count (a sibling such as `steam-<appID>-windows` may be a stale
    /// pre-`prefix/` layout), and one with `drive_c` wins.
    private func prefixRoots(stem: String) -> [URL] {
        let fm = FileManager.default
        let candidates = Self.subdirectories(of: root.appendingPathComponent("Prefixes"), withPrefix: stem)
            .map { $0.appendingPathComponent("prefix", isDirectory: true) }
            .filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
        let withDriveC = candidates.filter { fm.fileExists(atPath: $0.appendingPathComponent("drive_c").path) }
        return withDriveC + candidates.filter { !withDriveC.contains($0) }
    }

    private static func subdirectories(of dir: URL, withPrefix prefix: String) -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().filter { $0.hasPrefix(prefix) }.compactMap { name in
            let url = dir.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
        }
    }
}
