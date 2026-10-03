import AppKit
import LibertyCore
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    // MARK: Environment
    var crossOver: CrossOverInstall?
    var bottles: [Bottle] = []
    var selectedBottlePath: String? {
        didSet { UserDefaults.standard.set(selectedBottlePath, forKey: Keys.bottle) }
    }
    var crossOverPath: String? {
        didSet { UserDefaults.standard.set(crossOverPath, forKey: Keys.crossOver) }
    }
    var launchArguments: String {
        didSet { UserDefaults.standard.set(launchArguments, forKey: Keys.launchArgs) }
    }

    // MARK: State
    var mods: [InstalledMod] = []
    var conflicts: [String: [String]] = [:]
    var isGameRunning = false
    var gameUpdatedSinceLastSync = false
    var statusMessage: String?
    var errorMessage: String?
    var showImporter = false
    var isSteamRunning = false

    // Launch watchdog: set when a launch never produced a running game.
    var showStuckPrompt = false
    var watchdog = LaunchWatchdog()

    // Playtime
    var playtime = PlaytimeRecord()

    // Galactic War
    var war: WarStatus?
    var warUnavailable = false
    var lastWarUpdate: Date?

    // Crash helper
    var crashDetector = CrashDetector()
    var crashReport: CrashReport?

    // Setup assistant
    var showSetup = false

    // Discord
    var discordEnabled: Bool {
        didSet { UserDefaults.standard.set(discordEnabled, forKey: Keys.discordEnabled); updateDiscord() }
    }
    var discordAppID: String {
        didSet { UserDefaults.standard.set(discordAppID, forKey: Keys.discordAppID); discord = nil; updateDiscord() }
    }
    var discord: DiscordRPC?
    var gameStartedAt: Date?

    // Nexus account (premium accounts can install from the browser directly)
    var nexusUser: NexusUser?

    // Profiles & presets
    var profiles: [ModProfile] = []
    var customPresets: [PerformancePreset] = []

    // Nexus Mods
    var nexusAPIKey: String {
        didSet { Keychain.set(nexusAPIKey, for: Keys.nexusKeychain) }
    }
    var nexusDownloads: [String] = []
    var isCheckingModUpdates = false

    // App updates
    var availableUpdate: ReleaseInfo?
    var isInstallingUpdate = false
    var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: Keys.autoUpdate) }
    }

    let store: ModStore?
    let backups: BackupManager?
    let profileStore = ModProfileStore()
    let presetStore = PresetStore()
    let playtimeStore = PlaytimeStore()
    let supportDirectory = ModStore.defaultRoot
    private var monitoring = false

    private enum Keys {
        static let bottle = "selectedBottlePath"
        static let crossOver = "crossOverPath"
        static let launchArgs = "launchArguments"
        static let buildID = "lastDeployedBuildID"
        static let autoUpdate = "autoCheckUpdates"
        static let nexusKeychain = "nexus-api-key"
        static let discordEnabled = "discordEnabled"
        static let discordAppID = "discordAppID"
        static let setupSeen = "setupSeen"
    }

    init() {
        LibertyLog.shared.configure(fileURL: ModStore.defaultRoot.appendingPathComponent("Logs/liberty-loader.log"))
        selectedBottlePath = UserDefaults.standard.string(forKey: Keys.bottle)
        crossOverPath = UserDefaults.standard.string(forKey: Keys.crossOver)
        launchArguments = UserDefaults.standard.string(forKey: Keys.launchArgs) ?? ""
        store = try? ModStore()
        backups = try? BackupManager(directory: ModStore.defaultRoot.appendingPathComponent("Backups"))
        nexusAPIKey = Keychain.get(Keys.nexusKeychain) ?? ""
        autoCheckUpdates = UserDefaults.standard.object(forKey: Keys.autoUpdate) as? Bool ?? true
        discordEnabled = UserDefaults.standard.object(forKey: Keys.discordEnabled) as? Bool ?? true
        discordAppID = UserDefaults.standard.string(forKey: Keys.discordAppID) ?? DiscordRPC.bundledApplicationID
        mods = store?.mods ?? []
        profiles = profileStore.profiles
        customPresets = presetStore.custom
        playtime = playtimeStore.record
    }

    var setupSeen: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.setupSeen) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.setupSeen) }
    }

    /// Game or Steam is running in a bottle; bottle/registry files must not be edited then.
    var isBottleBusy: Bool { isGameRunning || isSteamRunning }

    var game: GamePaths? {
        let withGame = bottles.filter { $0.game != nil }
        return (withGame.first { $0.url.path == selectedBottlePath } ?? withGame.first)?.game
    }

    var deployer: PatchDeployer? {
        game.map { PatchDeployer(dataDir: $0.dataDir, stateDirectory: supportDirectory) }
    }

    // MARK: Discovery

    func refresh() {
        crossOver = CrossOverLocator.locate(preferred: crossOverPath.map { URL(fileURLWithPath: $0) })
        bottles = BottleScanner().bottles()
        if selectedBottlePath == nil { selectedBottlePath = game?.bottleURL.path }
        isGameRunning = GameLauncher.isGameRunning()
        let lastBuild = UserDefaults.standard.string(forKey: Keys.buildID)
        gameUpdatedSinceLastSync = lastBuild != nil && game?.buildID != nil && lastBuild != game?.buildID
        reloadMods()
    }

    // MARK: Launch

    func launch() {
        guard let crossOver else { return fail(LibertyError.crossOverNotFound) }
        guard let game else { return fail(LibertyError.gameNotFound) }
        do {
            try syncMods()
            let args = launchArguments.split(separator: " ").map(String.init)
            let command = try GameLauncher.command(crossOver: crossOver, game: game, launchArguments: args)
            try GameLauncher.launch(command)
            statusMessage = String(localized: "Launching Helldivers 2 via Steam in “\(game.bottleName)”…")
            watchdog.didLaunch()
            showStuckPrompt = false
        } catch {
            fail(error)
        }
    }

    func forceQuit() {
        guard let crossOver, let game else { return }
        crashDetector.userWillStopGame()
        do {
            try GameLauncher.killBottle(crossOver: crossOver, game: game)
            isGameRunning = false
            isSteamRunning = false
            watchdog.reset()
            showStuckPrompt = false
            statusMessage = String(localized: "Stopped all processes in “\(game.bottleName)”.")
        } catch {
            fail(error)
        }
    }

    /// Polls process state for the running indicator, playtime and the launch watchdog.
    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        Task {
            while true {
                let (game, steam) = await Task.detached {
                    (GameLauncher.isGameRunning(), GameLauncher.isSteamRunning())
                }.value
                let wasRunning = isGameRunning
                isGameRunning = game
                isSteamRunning = steam
                if game != wasRunning { gameRunningChanged(to: game) }
                if lastWarUpdate.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
                    lastWarUpdate = Date()
                    Task { await refreshWar() }
                }
                playtimeStore.update(isRunning: game)
                playtime = playtimeStore.record
                if watchdog.check(gameRunning: game) {
                    showStuckPrompt = true
                    watchdog.reset()
                }
                try? await Task.sleep(for: .seconds(game ? 15 : 5))
            }
        }
    }

    func retryLaunch() {
        forceQuit()
        Task {
            try? await Task.sleep(for: .seconds(3))
            launch()
        }
    }

    // MARK: Mods

    func reloadMods() {
        mods = store?.mods ?? []
        profiles = profileStore.profiles
        customPresets = presetStore.custom
        if let store, let deployer {
            conflicts = deployer.plan(for: store.resolvedEnabledMods()).conflicts
        }
    }

    func install(_ urls: [URL]) {
        guard let store else { return }
        var installed = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try store.install(from: url)
                installed += 1
            } catch {
                fail(error, context: url.lastPathComponent)
            }
        }
        if installed > 0 { statusMessage = installed == 1 ? String(localized: "Installed 1 mod.") : String(localized: "Installed \(installed) mods.") }
        reloadMods()
    }

    func update(_ mod: InstalledMod) {
        perform { try store?.update(mod) }
    }

    func uninstall(_ mod: InstalledMod) {
        perform { try store?.uninstall(mod.id) }
    }

    func move(from source: IndexSet, to destination: Int) {
        perform { try store?.move(fromOffsets: source, toOffset: destination) }
    }

    func setAllEnabled(_ enabled: Bool) {
        perform { try store?.setAllEnabled(enabled) }
    }

    func syncMods() throws {
        guard let store, let deployer else { return }
        guard !isGameRunning else { return }
        let plan = try deployer.sync(store.resolvedEnabledMods())
        conflicts = plan.conflicts
        UserDefaults.standard.set(game?.buildID, forKey: Keys.buildID)
        gameUpdatedSinceLastSync = false
    }

    func applyModsNow() {
        perform {
            try syncMods()
            statusMessage = String(localized: "Mods applied to the game folder.")
        }
    }

    func purgeMods() {
        perform {
            try deployer?.purge()
            statusMessage = String(localized: "Removed all mod files. The game folder is vanilla again.")
        }
    }

    func revealModFolder(_ mod: InstalledMod) {
        guard let store else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.folderURL(for: mod)])
    }

    // MARK: Helpers

    func perform(_ work: () throws -> Void) {
        do { try work() } catch { fail(error) }
        reloadMods()
    }

    func fail(_ error: Error, context: String? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorMessage = context.map { "\($0): \(message)" } ?? message
        LibertyLog.shared.error(errorMessage ?? message)
    }
}
