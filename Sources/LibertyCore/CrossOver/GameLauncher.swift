import Foundation

public struct LaunchCommand: Equatable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
}

/// Starts Helldivers 2 through Steam inside the CrossOver bottle.
public enum GameLauncher {
    /// Builds the CrossOver `wine` invocation. Launching through Steam keeps Steam auth and anti-cheat happy.
    public static func command(
        crossOver: CrossOverInstall,
        game: GamePaths,
        launchArguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> LaunchCommand {
        guard let steamPath = game.steamWindowsPath else { throw LibertyError.gameNotFound }
        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        return LaunchCommand(
            executableURL: crossOver.wineURL,
            arguments: ["--bottle", game.bottleName, steamPath, "-applaunch", GamePaths.steamAppID] + launchArguments,
            environment: env
        )
    }

    @discardableResult
    public static func launch(_ command: LaunchCommand) throws -> Process {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        LibertyLog.shared.info("Launched: \(command.executableURL.path) \(command.arguments.joined(separator: " "))")
        return process
    }

    public static func isGameRunning() -> Bool {
        (try? Shell.run("/usr/bin/pgrep", ["-if", "helldivers2.exe"]).status) == 0
    }

    /// Steam running in any bottle (it rewrites the bottle's registry when it exits).
    public static func isSteamRunning() -> Bool {
        (try? Shell.run("/usr/bin/pgrep", ["-if", "steam\\.exe"]).status) == 0
    }

    /// Force-quits every Windows process in the bottle (the game, Steam, stuck helpers).
    public static func killBottle(crossOver: CrossOverInstall, game: GamePaths) throws {
        try Shell.run(crossOver.wineURL.path, ["--bottle", game.bottleName, "wineboot", "--kill"])
        LibertyLog.shared.info("Killed Wine processes in bottle \(game.bottleName)")
    }
}
