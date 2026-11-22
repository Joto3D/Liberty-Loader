import Foundation

/// Where a Helldivers 2 install came from.
///
/// Liberty Loader was built around CrossOver, which keeps the game inside a
/// bottle at a fixed Steam-shaped path. Obelisk does not: it keeps the game in
/// its own `Games` tree and the Wine prefix separately, so nothing can be
/// derived from a single bottle URL. This enum is how the rest of the app asks
/// "which kind of install is this?" instead of assuming.
public enum InstallSource: Equatable, Sendable {
    /// A CrossOver bottle under `~/Library/Application Support/CrossOver/Bottles`.
    case crossOver
    /// An Obelisk install under `~/Library/Application Support/com.zagrios.obelisk`.
    case obelisk

    public var displayName: String {
        switch self {
        case .crossOver: return "CrossOver"
        case .obelisk: return "Obelisk"
        }
    }

    /// Obelisk runs the game itself; Liberty Loader can mod it but must not
    /// try to launch it through CrossOver's wine.
    public var canLaunchThroughCrossOver: Bool { self == .crossOver }

    /// Only Steam-managed installs carry an `appmanifest_*.acf` with a build id.
    /// Obelisk has none, so update detection has to fingerprint the executable.
    public var hasSteamAppManifest: Bool { self == .crossOver }
}

/// One discovered Helldivers 2 install, whatever manages it.
public struct GameInstall: Identifiable, Equatable, Sendable {
    public var id: String { paths.gameRoot.path }
    /// What to show in a picker, e.g. a bottle name or "Obelisk".
    public let name: String
    public let paths: GamePaths

    public init(name: String, paths: GamePaths) {
        self.name = name
        self.paths = paths
    }

    public var source: InstallSource { paths.source }
}

/// Finds every Helldivers 2 install on the machine, from every supported source.
///
/// This is the entry point the app should use instead of `BottleScanner`
/// directly, so adding a source later does not mean touching callers again.
public struct InstallScanner: Sendable {
    public let bottles: BottleScanner
    public let obelisk: ObeliskScanner

    public init(bottles: BottleScanner = BottleScanner(),
                obelisk: ObeliskScanner = ObeliskScanner()) {
        self.bottles = bottles
        self.obelisk = obelisk
    }

    /// Resolves a persisted selection against a list of installs.
    ///
    /// Liberty Loader has always stored the chosen install as a bottle path.
    /// Obelisk installs have no bottle, so the key is now the game root — but
    /// settings saved before this change still hold a bottle path, and a user
    /// who selected the CrossOver shim bottle must not silently get a different
    /// install after upgrading. Both spellings are therefore accepted.
    public static func resolve(key: String?, among installs: [GameInstall]) -> GameInstall? {
        guard let key, !key.isEmpty else { return installs.first }
        return installs.first { $0.id == key }
            ?? installs.first { $0.paths.bottleURL.path == key }
            ?? installs.first
    }

    /// CrossOver bottles that contain the game, then Obelisk installs.
    public func installs() -> [GameInstall] {
        let fromBottles = bottles.bottlesWithGame().compactMap { bottle -> GameInstall? in
            guard let paths = bottle.game else { return nil }
            return GameInstall(name: bottle.name, paths: paths)
        }
        let fromObelisk = obelisk.installs().map {
            GameInstall(name: InstallSource.obelisk.displayName, paths: $0)
        }
        return fromBottles + fromObelisk
    }
}

extension InstallFingerprint {
    /// Whether to warn that the game changed underneath the deployed mods.
    ///
    /// Only a confirmed change warns. `.notComparable` means the two
    /// fingerprints are different kinds — which happens when the user switches
    /// between a CrossOver install (Steam build id) and an Obelisk one
    /// (executable hash). That is a change of install, not evidence the game
    /// was patched, so it must not raise a false "Helldivers 2 was updated".
    /// Callers should re-record the fingerprint when this returns false but the
    /// comparison was not `.same`.
    public static func gameChanged(current: InstallFingerprint?,
                                   lastDeployed: InstallFingerprint?) -> Bool {
        guard let current, let lastDeployed else { return false }
        return current.compare(to: lastDeployed) == .changed
    }
}
