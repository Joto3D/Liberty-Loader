import AppKit
import LibertyCore

/// What the crash helper shows after a suspected crash.
struct CrashReport: Equatable {
    var date: Date
    var files: [URL]
}

extension AppModel {
    // MARK: Running state

    func gameRunningChanged(to running: Bool) {
        if running {
            crashDetector.gameStarted()
            gameStartedAt = Date()
            crashReport = nil
        } else {
            gameStartedAt = nil
            if crashDetector.gameStopped(), let game {
                let since = Date().addingTimeInterval(-600)
                crashReport = CrashReport(date: Date(), files: CrashDetector.recentCrashFiles(in: game.appDataDir, since: since))
                LibertyLog.shared.info("Suspected crash; \(crashReport?.files.count ?? 0) crash file(s) found")
            }
        }
        updateDiscord()
    }

    // MARK: Galactic War

    func refreshWar() async {
        do {
            war = try await WarClient.fetch()
            warUnavailable = false
        } catch {
            warUnavailable = war == nil
        }
    }

    // MARK: Discord

    var discordAvailable: Bool { !discordAppID.trimmingCharacters(in: .whitespaces).isEmpty }

    func updateDiscord() {
        guard discordEnabled, discordAvailable, isGameRunning else {
            discord?.setActivity(nil)
            return
        }
        if discord == nil { discord = DiscordRPC(applicationID: discordAppID.trimmingCharacters(in: .whitespaces)) }
        let count = mods.filter(\.enabled).count
        let state = count == 0 ? String(localized: "Diving via Liberty Loader") : String(localized: "Diving with \(count) mods")
        discord?.setActivity(.init(details: "Helldivers 2", state: state, start: gameStartedAt))
    }

    // MARK: Crash helper actions

    func disableModsAndRetry() {
        crashReport = nil
        setAllEnabled(false)
        launch()
    }

    func switchGraphicsBackend() {
        guard let game else { return }
        perform {
            var config = (try? BottleConfig.load(from: game.bottleConfigURL)) ?? BottleConfig(text: "")
            let next: BottleConfig.GraphicsBackend = config.graphicsBackend == .dxvk ? .d3dmetal : .dxvk
            try backups?.backup(game.bottleConfigURL, label: "Crash helper")
            config.graphicsBackend = next
            try config.write(to: game.bottleConfigURL)
            statusMessage = String(localized: "Graphics backend switched to \(next.displayName). Try launching again.")
        }
    }

    func verifyGameFiles() {
        runSteamURL("steam://validate/\(GamePaths.steamAppID)")
    }

    func installGameWithSteam() {
        runSteamURL("steam://install/\(GamePaths.steamAppID)")
    }

    private func runSteamURL(_ url: String) {
        guard let crossOver else { return fail(LibertyError.crossOverNotFound) }
        let scanner = BottleScanner()
        let bottleURL = game?.bottleURL ?? SetupStatus(crossOver: crossOver, bottles: bottles).steamBottle
        guard let bottleURL, let steamRoot = scanner.steamRoot(inBottle: bottleURL),
              let command = GameLauncher.steamURLCommand(crossOver: crossOver, bottleURL: bottleURL, steamRoot: steamRoot, url: url) else {
            return fail(LibertyError.gameNotFound)
        }
        do { try GameLauncher.launch(command) } catch { fail(error) }
    }

    func revealCrashFile() {
        if let file = crashReport?.files.first {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else if let game {
            NSWorkspace.shared.open(game.appDataDir)
        }
    }

    // MARK: Setup assistant

    var setupStatus: SetupStatus { SetupStatus(crossOver: crossOver, bottles: bottles) }

    func showSetupIfNeeded() {
        if !setupSeen || !setupStatus.isReady { showSetup = true }
    }

    func openCrossOver() {
        if let app = crossOver?.appURL {
            NSWorkspace.shared.open(app)
        } else {
            NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover")!)
        }
    }

    // MARK: Mod browser

    func refreshNexusUser() async {
        guard !nexusAPIKey.isEmpty else { nexusUser = nil; return }
        nexusUser = try? await NexusClient(apiKey: nexusAPIKey).validateUser()
    }

    /// Premium accounts download directly; free accounts are sent to the files page,
    /// where "Mod Manager Download" hands the file back to Liberty Loader.
    func installFromBrowser(_ mod: NexusModSummary) async {
        if nexusUser == nil { await refreshNexusUser() }
        guard nexusUser?.is_premium == true else {
            NSWorkspace.shared.open(URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(mod.id)?tab=files")!)
            statusMessage = String(localized: "Click “Mod Manager Download” on Nexus Mods to finish installing.")
            return
        }
        do {
            let files = try await NexusClient(apiKey: nexusAPIKey).files(modID: mod.id)
            guard let file = NexusClient.preferredFile(files),
                  let url = URL(string: "nxm://\(NexusClient.gameDomain)/mods/\(mod.id)/files/\(file.file_id)"),
                  let link = NXMLink(url: url) else {
                throw NexusClient.ClientError.noDownloadLink
            }
            await installFromNexus(link)
        } catch {
            fail(error, context: mod.name)
        }
    }

    func installedMod(for nexusID: Int) -> InstalledMod? {
        mods.first { $0.nexusModID == nexusID }
    }
}
