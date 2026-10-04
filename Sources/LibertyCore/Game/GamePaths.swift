import Foundation

/// All locations Liberty Loader cares about for one Helldivers 2 install inside a CrossOver bottle.
public struct GamePaths: Equatable, Sendable {
    public static let steamAppID = "553850"

    /// `~/Library/Application Support/CrossOver/Bottles/<name>`
    public let bottleURL: URL
    /// Folder that contains `steam.exe`.
    public let steamRootURL: URL
    /// Steam library folder that contains `steamapps/common/Helldivers 2`.
    public let libraryURL: URL

    public init(bottleURL: URL, steamRootURL: URL, libraryURL: URL) {
        self.bottleURL = bottleURL
        self.steamRootURL = steamRootURL
        self.libraryURL = libraryURL
    }

    public var bottleName: String { bottleURL.lastPathComponent }
    public var driveC: URL { bottleURL.appendingPathComponent("drive_c") }
    public var bottleConfigURL: URL { bottleURL.appendingPathComponent("cxbottle.conf") }

    public var gameRoot: URL { libraryURL.appendingPathComponent("steamapps/common/Helldivers 2") }
    public var dataDir: URL { gameRoot.appendingPathComponent("data") }
    public var executableURL: URL { gameRoot.appendingPathComponent("bin/helldivers2.exe") }
    public var appManifestURL: URL {
        libraryURL.appendingPathComponent("steamapps/appmanifest_\(Self.steamAppID).acf")
    }
    public var steamExecutableURL: URL { steamRootURL.appendingPathComponent("steam.exe") }

    /// Windows-style path of steam.exe as seen from inside the bottle, e.g. `C:\Program Files (x86)\Steam\steam.exe`.
    public var steamWindowsPath: String? { Self.windowsPath(for: steamExecutableURL, driveC: driveC) }

    /// `%APPDATA%\Arrowhead\Helldivers2\user_settings.config` for whichever Windows user exists in the bottle.
    public var userSettingsURL: URL {
        let usersDir = driveC.appendingPathComponent("users")
        let relative = "AppData/Roaming/Arrowhead/Helldivers2/user_settings.config"
        let fm = FileManager.default
        let users = ((try? fm.contentsOfDirectory(atPath: usersDir.path)) ?? [])
            .filter { $0 != "Public" && !$0.hasPrefix(".") }
            .sorted()
        for user in users {
            let candidate = usersDir.appendingPathComponent(user).appendingPathComponent(relative)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return usersDir.appendingPathComponent("crossover").appendingPathComponent(relative)
    }

    /// `drive_c/users/<name>` folders of the bottle's Windows users (without "Public").
    public var windowsUserDirs: [URL] {
        let usersDir = driveC.appendingPathComponent("users")
        return ((try? FileManager.default.contentsOfDirectory(atPath: usersDir.path)) ?? [])
            .filter { $0 != "Public" && !$0.hasPrefix(".") }
            .sorted()
            .map { usersDir.appendingPathComponent($0) }
    }

    /// `%LOCALAPPDATA%` of every Windows user in the bottle.
    public var localAppDataDirs: [URL] {
        windowsUserDirs.map { $0.appendingPathComponent("AppData/Local") }
    }

    /// Current Steam build id of the game, used to warn about updates that break mods.
    public var buildID: String? {
        guard let text = try? String(contentsOf: appManifestURL, encoding: .utf8) else { return nil }
        return VDF.value(forKey: "buildid", in: text)
    }

    static func windowsPath(for url: URL, driveC: URL) -> String? {
        let full = url.standardizedFileURL.path
        let root = driveC.standardizedFileURL.path
        guard full.hasPrefix(root + "/") else { return nil }
        let relative = full.dropFirst(root.count + 1)
        return "C:\\" + relative.replacingOccurrences(of: "/", with: "\\")
    }
}
