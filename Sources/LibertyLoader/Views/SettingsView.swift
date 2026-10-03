import AppKit
import LibertyCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyDraft: String?
    @State private var showAllBackups = false

    var body: some View {
        @Bindable var model = model
        HDPage {
            HDPageTitle(title: "Settings", subtitle: "Paths, Nexus Mods, updates and backups.")
            StatusBanner()

            section("CrossOver") {
                InfoRow(label: "Location", value: model.crossOver?.appURL.path ?? String(localized: "Not found"))
                InfoRow(label: "Version", value: model.crossOver?.version ?? "–")
                Button("Choose CrossOver.app…", action: chooseCrossOver)
                    .buttonStyle(HDSecondaryButtonStyle())
            }

            section("Bottle") {
                let bottlesWithGame = model.bottles.filter { $0.game != nil }
                if bottlesWithGame.isEmpty {
                    Text("No bottle with Helldivers 2 found in \(BottleScanner.defaultBottlesDirectory.path).")
                        .foregroundStyle(Color.hdMuted)
                } else {
                    HStack {
                        Text("Helldivers 2 bottle").foregroundStyle(Color.hdText)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.game?.bottleURL.path ?? "" },
                            set: { model.selectedBottlePath = $0; model.refresh() }
                        )) {
                            ForEach(bottlesWithGame) { Text(verbatim: $0.name).tag($0.url.path) }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                }
                if let game = model.game {
                    InfoRow(label: "Game folder", value: game.gameRoot.path)
                    HStack {
                        Button("Reveal Game Folder") { NSWorkspace.shared.activateFileViewerSelecting([game.gameRoot]) }
                        Button("Rescan") { model.refresh() }
                    }
                    .buttonStyle(HDSecondaryButtonStyle())
                }
            }

            section("Launch") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Extra launch options", text: $model.launchArguments, prompt: Text(verbatim: "--use-d3d11"))
                        .textFieldStyle(.roundedBorder)
                    Text("Passed to the game the same way as Steam's launch options.")
                        .font(.caption).foregroundStyle(Color.hdMuted)
                }
            }

            section("Nexus Mods") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SecureField("Personal API key", text: Binding(
                            get: { apiKeyDraft ?? model.nexusAPIKey },
                            set: { apiKeyDraft = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        if model.nexusAPIKey.isEmpty {
                            StatusPill(color: .hdWarning, text: "Not set")
                        } else {
                            StatusPill(color: .hdSuccess, text: "Connected")
                        }
                    }
                    HStack {
                        Button("Save Key") {
                            model.nexusAPIKey = (apiKeyDraft ?? model.nexusAPIKey).trimmingCharacters(in: .whitespacesAndNewlines)
                            apiKeyDraft = nil
                            model.statusMessage = String(localized: "Nexus Mods API key saved.")
                        }
                        .buttonStyle(HDPrimaryButtonStyle())
                        .disabled(apiKeyDraft == nil)
                        Button("Get My API Key") {
                            NSWorkspace.shared.open(URL(string: "https://www.nexusmods.com/users/myaccount?tab=api")!)
                        }
                        .buttonStyle(HDSecondaryButtonStyle())
                        Button("Browse Helldivers 2 Mods") {
                            NSWorkspace.shared.open(URL(string: "https://www.nexusmods.com/helldivers2/mods/")!)
                        }
                        .buttonStyle(HDSecondaryButtonStyle())
                    }
                    Text("With a key, the “Mod Manager Download” button on Nexus Mods installs mods straight into Liberty Loader, and mod updates can be checked. The key is stored in your Keychain.")
                        .font(.caption).foregroundStyle(Color.hdMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Discord") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show “Playing Helldivers 2” in Discord", isOn: $model.discordEnabled)
                        .toggleStyle(.switch)
                        .tint(.hdYellow)
                        .disabled(!model.discordAvailable)
                    HStack {
                        TextField("Discord Application ID", text: $model.discordAppID)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        Button("Developer Portal") {
                            NSWorkspace.shared.open(URL(string: "https://discord.com/developers/applications")!)
                        }
                        .buttonStyle(HDSecondaryButtonStyle())
                    }
                    Text("Discord needs an application ID to show a status. Create a free application named “Liberty Loader” in the Discord Developer Portal and paste its Application ID here. Discord must be running on this Mac.")
                        .font(.caption).foregroundStyle(Color.hdMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Setup assistant") {
                HStack {
                    Text("Walks you through CrossOver, Steam and Helldivers 2 again.")
                        .foregroundStyle(Color.hdMuted)
                    Spacer()
                    Button("Run Setup Assistant") { model.showSetup = true }
                        .buttonStyle(HDSecondaryButtonStyle())
                }
            }

            section("App updates") {
                InfoRow(label: "Installed version", value: model.currentVersionText)
                Toggle("Check for updates automatically", isOn: $model.autoCheckUpdates)
                    .toggleStyle(.switch)
                    .tint(.hdYellow)
                HStack {
                    Button("Check Now") { Task { await model.checkForUpdates(userInitiated: true) } }
                        .buttonStyle(HDSecondaryButtonStyle())
                    if let release = model.availableUpdate {
                        Button {
                            Task { await model.installUpdate() }
                        } label: {
                            if model.isInstallingUpdate {
                                Text("Installing…")
                            } else {
                                Text("Install \(release.version.description)")
                            }
                        }
                        .buttonStyle(HDPrimaryButtonStyle())
                        .disabled(model.isInstallingUpdate)
                    }
                }
            }

            backupsSection

            section("Support") {
                HStack {
                    Button("Open Liberty Loader Folder") { NSWorkspace.shared.open(model.supportDirectory) }
                    if let log = LibertyLog.shared.fileURL {
                        Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                    }
                }
                .buttonStyle(HDSecondaryButtonStyle())
            }
        }
        .navigationTitle("Settings")
    }

    private var backupsSection: some View {
        let backups = model.backups?.backups.sorted { $0.createdAt > $1.createdAt } ?? []
        let visible = showAllBackups ? backups : Array(backups.prefix(5))
        return section("Backups") {
            if backups.isEmpty {
                Text("No backups yet.").foregroundStyle(Color.hdMuted)
            }
            ForEach(visible) { backup in
                HStack {
                    Image(systemName: backup.isOriginal ? "lock.fill" : "clock.arrow.circlepath")
                        .foregroundStyle(backup.isOriginal ? Color.hdYellow : Color.hdMuted)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: backup.label).foregroundStyle(Color.hdText)
                            if backup.isOriginal { HDTag(text: "Original") }
                        }
                        Text(verbatim: "\(URL(fileURLWithPath: backup.originalPath).lastPathComponent) · \(backup.createdAt.formatted())")
                            .font(.caption).foregroundStyle(Color.hdMuted)
                    }
                    Spacer()
                    Button("Restore") { model.perform { try model.backups?.restore(backup) } }
                        .buttonStyle(HDSecondaryButtonStyle())
                }
            }
            if backups.count > 5 {
                Button {
                    withAnimation { showAllBackups.toggle() }
                } label: {
                    if showAllBackups {
                        Text("Show fewer")
                    } else {
                        Text("Show all \(backups.count) backups")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.hdYellow)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HDSectionHeader(title: title)
            HDPanel {
                VStack(alignment: .leading, spacing: 12) { content() }
            }
        }
    }

    private func chooseCrossOver() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard CrossOverLocator.inspect(url) != nil else {
            model.errorMessage = String(localized: "That app doesn't look like CrossOver.")
            return
        }
        model.crossOverPath = url.path
        model.refresh()
    }
}

@MainActor
struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Color.hdMuted)
            Spacer()
            Text(verbatim: value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.hdText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
