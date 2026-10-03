import AppKit
import LibertyCore

extension AppModel {
    var currentVersion: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    var currentVersionText: String { currentVersion?.description ?? "development build" }

    func checkForUpdates(userInitiated: Bool) async {
        guard let current = currentVersion else {
            if userInitiated { statusMessage = "Updates are only available in the packaged app." }
            return
        }
        do {
            availableUpdate = try await UpdateChecker.checkForUpdate(current: current)
            if userInitiated, availableUpdate == nil { statusMessage = "Liberty Loader \(current) is up to date." }
        } catch {
            if userInitiated { fail(error) }
        }
    }

    /// Downloads the new version, swaps it in for the running app and relaunches.
    func installUpdate() async {
        guard let release = availableUpdate else { return }
        guard let zipURL = release.zipURL else {
            NSWorkspace.shared.open(release.dmgURL ?? release.pageURL)
            return
        }
        isInstallingUpdate = true
        defer { isInstallingUpdate = false }
        do {
            let current = Bundle.main.bundleURL
            guard current.pathExtension == "app",
                  FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
                NSWorkspace.shared.open(release.pageURL)
                return
            }
            let (zip, _) = try await URLSession.shared.download(from: zipURL)
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("LibertyUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, workDir.path])
            let items = try FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            // Wait for this process to quit, replace the bundle, then reopen it.
            let script = """
            while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.5; done
            /bin/rm -rf "$1" && /bin/mv "$2" "$1" && /usr/bin/xattr -dr com.apple.quarantine "$1"
            /usr/bin/open "$1"
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script, "updater", current.path, newApp.path]
            try process.run()
            LibertyLog.shared.info("Installing update \(release.version)")
            NSApp.terminate(nil)
        } catch {
            fail(error, context: "Update")
        }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }

    // MARK: Custom presets

    func saveCustomPreset(named name: String, config: UserSettingsConfig, bottle: BottleConfig?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        perform {
            try presetStore.add(PerformancePreset.custom(name: trimmed, config: config, bottle: bottle))
            statusMessage = "Saved preset “\(trimmed)”."
        }
    }

    func deleteCustomPreset(_ preset: PerformancePreset) {
        perform { try presetStore.delete(id: preset.id) }
    }
}
