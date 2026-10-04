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

// MARK: - Mod diagnosis & requirements

extension AppModel {
    @discardableResult
    func runDiagnostics() -> DiagnosticsReport? {
        guard let store, let deployer else { diagnostics = nil; return nil }
        var report = ModDiagnostics.run(
            store: store,
            deployer: deployer,
            buildChanged: gameUpdatedSinceLastSync,
            gameRunning: isGameRunning
        )
        if let game {
            report.logs = ModLogs.find(game: game)
            // A shared loader (pinned last, "loader" in its name or text) should log every game session.
            let loader = mods.first { mod in
                mod.enabled && mod.loadOrderPin == .bottom
                    && (mod.name + " " + (mod.description ?? "")).localizedCaseInsensitiveContains("loader")
            }
            if let loader, ModLogs.loaderDidNotRun(
                logs: report.logs,
                source: nil,
                sessionStart: playtime.lastSessionStart,
                sessionEnd: playtime.lastSessionEnd,
                lastDeploy: UserDefaults.standard.object(forKey: "lastDeployDate") as? Date
            ) {
                report.global.append(.loaderDidNotRun(name: loader.name))
            }
        }
        diagnostics = report
        return report
    }

    func openDiagnostics() {
        diagnosticsHint = false
        runDiagnostics()
        showDiagnostics = true
    }

    func findMod(_ id: UUID) -> InstalledMod? {
        mods.first { $0.id == id }
    }

    /// Moves a mod to the end of the load order so it wins over overlapping mods.
    func moveToBottom(_ id: UUID) {
        guard let index = mods.firstIndex(where: { $0.id == id }) else { return }
        move(from: IndexSet(integer: index), to: mods.count)
        runDiagnostics()
    }

    func disable(_ id: UUID) {
        guard var mod = findMod(id) else { return }
        mod.enabled = false
        update(mod)
        runDiagnostics()
    }

    func applyAndRediagnose() {
        applyModsNow()
        runDiagnostics()
    }

    func missingRequirements(for mod: InstalledMod) -> [NexusRequirement] {
        mod.missingRequirements(installed: mods)
    }

    /// Installs a required Nexus mod, or opens its page for external tools.
    func installRequirement(_ requirement: NexusRequirement) async {
        guard !requirement.isExternal, let id = requirement.modID else {
            if let url = requirement.pageURL { NSWorkspace.shared.open(url) }
            return
        }
        let summary = NexusModSummary(
            modID: id, name: requirement.name, summary: requirement.notes,
            pictureURL: nil, endorsements: nil, author: nil, version: nil
        )
        await installFromBrowser(summary)
        runDiagnostics()
    }

    /// Re-reads requirements from Nexus for every mod installed from there.
    func refreshRequirements() async {
        guard let store, !nexusAPIKey.isEmpty else { return }
        let client = NexusClient(apiKey: nexusAPIKey)
        for mod in store.mods {
            guard let id = mod.nexusModID, let requirements = await client.requirements(modID: id) else { continue }
            var updated = mod
            updated.requirements = requirements
            try? store.update(updated)
        }
        reloadMods()
        runDiagnostics()
        await autoInstallMissingRequirements()
    }

    // MARK: Automatic requirement installs

    /// Missing Nexus requirements of all enabled mods, one entry per required mod.
    func allMissingRequirements() -> [NexusRequirement] {
        var seen: Set<Int> = []
        var result: [NexusRequirement] = []
        for mod in mods where mod.enabled {
            for requirement in mod.missingRequirements(installed: mods) {
                guard let id = requirement.modID, seen.insert(id).inserted else { continue }
                result.append(requirement)
            }
        }
        return result
    }

    /// Installs whatever enabled mods still need, including requirements of requirements.
    /// Premium accounts download directly; free accounts get the Nexus pages opened once,
    /// where "Mod Manager Download" hands the files back to Liberty Loader.
    func autoInstallMissingRequirements(force: Bool = false) async {
        guard autoInstallRequirements || force, !isAutoInstalling, !nexusAPIKey.isEmpty else { return }
        isAutoInstalling = true
        defer { isAutoInstalling = false }

        for _ in 0..<4 { // a few levels of nested requirements
            let missing = allMissingRequirements()
            guard !missing.isEmpty else { return }
            if nexusUser == nil { await refreshNexusUser() }

            if nexusUser?.is_premium == true {
                let pending = missing.filter { !attemptedRequirements.contains($0.modID ?? -1) }
                guard !pending.isEmpty else { return }
                for requirement in pending {
                    if let id = requirement.modID { attemptedRequirements.insert(id) }
                    statusMessage = String(localized: "Installing required mod “\(requirement.name)”…")
                    await installRequirement(requirement)
                }
            } else {
                let toOpen = missing.filter { !openedRequirementPages.contains($0.modID ?? -1) }.prefix(5)
                guard !toOpen.isEmpty else { return }
                for requirement in toOpen {
                    guard let id = requirement.modID,
                          let url = URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(id)?tab=files") else { continue }
                    openedRequirementPages.insert(id)
                    NSWorkspace.shared.open(url)
                }
                let count = toOpen.count
                statusMessage = String(localized: "Opened \(count) required mods on Nexus Mods. Click “Mod Manager Download” on each page and Liberty Loader installs them.")
                return
            }
        }
    }
}

// MARK: - Mod guide

extension AppModel {
    func showGuide(for mod: InstalledMod) {
        guideModID = mod.id
    }

    /// Fetches the full Nexus page description once and stores it with the mod.
    @discardableResult
    func loadNexusDescription(for id: UUID) async -> Bool {
        guard let store, let mod = findMod(id), let nexusID = mod.nexusModID,
              mod.nexusDescription == nil, !nexusAPIKey.isEmpty,
              let info = try? await NexusClient(apiKey: nexusAPIKey).mod(nexusID),
              let full = info.description, !full.isEmpty else { return false }
        var updated = mod
        updated.nexusDescription = full
        try? store.update(updated)
        reloadMods()
        return true
    }
}
