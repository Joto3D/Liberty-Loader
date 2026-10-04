import AppKit
import LibertyCore

extension AppModel {
    func handleOpenURL(_ url: URL) {
        if let link = NXMLink(url: url) {
            Task { await installFromNexus(link) }
        } else if url.isFileURL {
            install([url])
        }
    }

    /// Handles the "Mod Manager Download" button on nexusmods.com.
    func installFromNexus(_ link: NXMLink) async {
        guard link.game == NexusClient.gameDomain else {
            errorMessage = String(localized: "That Nexus link is for “\(link.game)”, not Helldivers 2.")
            return
        }
        let client = NexusClient(apiKey: nexusAPIKey)
        let label = String(localized: "Nexus mod \(link.modID)")
        nexusDownloads.append(label)
        defer { nexusDownloads.removeAll { $0 == label } }
        do {
            async let modInfo = client.mod(link.modID)
            async let fileInfo = client.file(link.fileID, mod: link.modID)
            let archive = try await client.download(client.downloadURL(for: link))
            let info = try? await modInfo
            let file = try? await fileInfo
            defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

            guard let store else { return }
            let existing = store.mods.first { $0.nexusModID == link.modID }
            var mod = try store.install(from: archive, replacing: existing?.id)
            mod.nexusModID = link.modID
            mod.nexusFileID = link.fileID
            mod.version = file?.version ?? info?.version
            mod.latestVersion = mod.version
            if existing == nil, let name = info?.name { mod.name = name }
            if mod.description == nil { mod.description = info?.summary }
            if let full = info?.description, !full.isEmpty { mod.nexusDescription = full }
            if let requirements = await client.requirements(modID: link.modID) { mod.requirements = requirements }
            try store.update(mod)
            try store.refreshPins()

            if let picture = info?.picture_url.flatMap(URL.init(string:)), store.previewImageURL(for: mod) == nil {
                await savePreview(picture, into: store.folderURL(for: mod))
            }
            statusMessage = existing == nil
                ? String(localized: "Installed “\(mod.name)” from Nexus Mods.")
                : String(localized: "Updated “\(mod.name)”.")
        } catch {
            fail(error, context: label)
        }
        reloadMods()
        autoApply()
        // The new mod may need others; fetch them in the background.
        Task { await autoInstallMissingRequirements() }
    }

    private func savePreview(_ url: URL, into folder: URL) async {
        guard let data = try? await URLSession.shared.data(from: url).0 else { return }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        try? data.write(to: folder.appendingPathComponent("preview.\(ext)"))
    }

    /// Asks Nexus Mods for the newest version of every mod that came from there.
    func checkModUpdates() async {
        guard let store, !nexusAPIKey.isEmpty else {
            errorMessage = NexusClient.ClientError.missingAPIKey.errorDescription
            return
        }
        isCheckingModUpdates = true
        defer { isCheckingModUpdates = false }
        let client = NexusClient(apiKey: nexusAPIKey)
        var updates = 0
        for mod in store.mods {
            guard let modID = mod.nexusModID, let info = try? await client.mod(modID) else { continue }
            var updated = mod
            updated.latestVersion = info.version
            if let full = info.description, !full.isEmpty { updated.nexusDescription = full }
            if let requirements = await client.requirements(modID: modID) { updated.requirements = requirements }
            try? store.update(updated)
            if updated.hasUpdate { updates += 1 }
        }
        statusMessage = updates == 0
            ? String(localized: "All Nexus mods are up to date.")
            : String(localized: "Mod updates available: \(updates)")
        reloadMods()
        await autoInstallMissingRequirements()
    }

    func openNexusPage(_ mod: InstalledMod) {
        guard let id = mod.nexusModID,
              let url = URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(id)?tab=files") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Profiles

    func saveProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        perform {
            try profileStore.save(name: trimmed, from: store?.mods ?? [])
            statusMessage = String(localized: "Saved profile “\(trimmed)”.")
        }
    }

    func applyProfile(_ profile: ModProfile) {
        perform {
            try store?.apply(profile)
            statusMessage = autoApplyMods
                ? String(localized: "Switched to profile “\(profile.name)”.")
                : String(localized: "Switched to profile “\(profile.name)”. Mods are applied on the next launch.")
        }
        autoApply()
    }

    func deleteProfile(_ profile: ModProfile) {
        perform { try profileStore.delete(profile.id) }
    }
}
