import Foundation

public struct Bottle: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    /// Set when Helldivers 2 is installed in this bottle.
    public let game: GamePaths?
}

/// Finds CrossOver bottles and the Helldivers 2 install inside them.
public struct BottleScanner {
    public static var defaultBottlesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles")
    }

    public let bottlesDirectory: URL

    public init(bottlesDirectory: URL = BottleScanner.defaultBottlesDirectory) {
        self.bottlesDirectory = bottlesDirectory
    }

    public func bottles() -> [Bottle] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: bottlesDirectory.path)) ?? []
        return names.sorted().compactMap { name in
            let url = bottlesDirectory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard !name.hasPrefix("."),
                  fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  fm.fileExists(atPath: url.appendingPathComponent("drive_c").path) else { return nil }
            return Bottle(name: name, url: url, game: findGame(inBottle: url))
        }
    }

    /// Bottles that actually contain Helldivers 2.
    public func bottlesWithGame() -> [Bottle] {
        bottles().filter { $0.game != nil }
    }

    public func findGame(inBottle bottleURL: URL) -> GamePaths? {
        let fm = FileManager.default
        let driveC = bottleURL.appendingPathComponent("drive_c")
        let steamRoots = ["Program Files (x86)/Steam", "Program Files/Steam"]
            .map { driveC.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }

        for steamRoot in steamRoots {
            var libraries = [steamRoot]
            let vdf = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
            if let text = try? String(contentsOf: vdf, encoding: .utf8) {
                libraries += VDF.values(forKey: "path", in: text).compactMap {
                    Self.bottleURL(forWindowsPath: $0, bottleURL: bottleURL)
                }
            }
            for library in libraries {
                let paths = GamePaths(bottleURL: bottleURL, steamRootURL: steamRoot, libraryURL: library)
                if fm.fileExists(atPath: paths.executableURL.path) || fm.fileExists(atPath: paths.dataDir.path) {
                    return paths
                }
            }
        }
        return nil
    }

    /// Converts `D:\SteamLibrary` into the matching macOS path inside the bottle.
    static func bottleURL(forWindowsPath windowsPath: String, bottleURL: URL) -> URL? {
        let chars = Array(windowsPath)
        guard chars.count >= 2, chars[1] == ":", chars[0].isLetter else { return nil }
        let drive = chars[0].lowercased()
        let rest = String(chars.dropFirst(2))
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let driveRoot: URL
        if drive == "c" {
            driveRoot = bottleURL.appendingPathComponent("drive_c")
        } else {
            driveRoot = bottleURL.appendingPathComponent("dosdevices/\(drive):").resolvingSymlinksInPath()
        }
        return rest.isEmpty ? driveRoot : driveRoot.appendingPathComponent(rest)
    }
}
