import Foundation

/// First-run checklist shown by the setup assistant.
public enum SetupStep: Int, CaseIterable, Sendable {
    case crossOver, steamBottle, game, preset, nexus
}

public struct SetupStatus: Equatable, Sendable {
    public var crossOverInstalled: Bool
    public var crossOverSupported: Bool
    public var steamBottle: URL?
    public var gameInstalled: Bool

    public init(crossOver: CrossOverInstall?, bottles: [Bottle], scanner: BottleScanner = BottleScanner()) {
        crossOverInstalled = crossOver != nil
        crossOverSupported = crossOver?.isSupportedVersion ?? false
        gameInstalled = bottles.contains { $0.game != nil }
        steamBottle = bottles.first { $0.game != nil }?.url
            ?? bottles.first { scanner.steamRoot(inBottle: $0.url) != nil }?.url
    }

    public func isDone(_ step: SetupStep) -> Bool {
        switch step {
        case .crossOver: return crossOverInstalled
        case .steamBottle: return steamBottle != nil
        case .game: return gameInstalled
        case .preset, .nexus: return false
        }
    }

    /// First required step that isn't done yet, else the first optional one.
    public var currentStep: SetupStep {
        [SetupStep.crossOver, .steamBottle, .game].first { !isDone($0) } ?? .preset
    }

    /// The app is usable once the required steps are done.
    public var isReady: Bool { crossOverInstalled && gameInstalled }
}

extension BottleScanner {
    /// Folder containing `steam.exe` in a bottle, if Steam is installed there.
    public func steamRoot(inBottle bottleURL: URL) -> URL? {
        let driveC = bottleURL.appendingPathComponent("drive_c")
        return ["Program Files (x86)/Steam", "Program Files/Steam"]
            .map { driveC.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("steam.exe").path) }
    }
}

extension GameLauncher {
    /// Runs a `steam://` URL (install, validate, …) with the bottle's Steam.
    public static func steamURLCommand(crossOver: CrossOverInstall, bottleURL: URL, steamRoot: URL, url: String) -> LaunchCommand? {
        let driveC = bottleURL.appendingPathComponent("drive_c")
        guard let steam = GamePaths.windowsPath(for: steamRoot.appendingPathComponent("steam.exe"), driveC: driveC) else { return nil }
        return LaunchCommand(
            executableURL: crossOver.wineURL,
            arguments: ["--bottle", bottleURL.lastPathComponent, steam, url],
            environment: ProcessInfo.processInfo.environment
        )
    }
}
