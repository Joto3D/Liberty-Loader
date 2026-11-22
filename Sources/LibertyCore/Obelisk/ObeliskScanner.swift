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
        // Implemented in a follow-up; the contract is what callers rely on.
        []
    }
}
