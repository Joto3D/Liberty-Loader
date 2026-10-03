import AppKit
import LibertyCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("CrossOver") {
                LabeledContent("Location", value: model.crossOver?.appURL.path ?? "Not found")
                LabeledContent("Version", value: model.crossOver?.version ?? "—")
                Button("Choose CrossOver.app…", action: chooseCrossOver)
            }

            Section("Bottle") {
                let bottlesWithGame = model.bottles.filter { $0.game != nil }
                if bottlesWithGame.isEmpty {
                    Text("No bottle with Helldivers 2 found in \(BottleScanner.defaultBottlesDirectory.path).")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Helldivers 2 bottle", selection: Binding(
                        get: { model.game?.bottleURL.path ?? "" },
                        set: { model.selectedBottlePath = $0; model.refresh() }
                    )) {
                        ForEach(bottlesWithGame) { Text($0.name).tag($0.url.path) }
                    }
                }
                if let game = model.game {
                    LabeledContent("Game folder", value: game.gameRoot.path)
                    HStack {
                        Button("Reveal Game Folder") { NSWorkspace.shared.activateFileViewerSelecting([game.gameRoot]) }
                        Button("Rescan") { model.refresh() }
                    }
                }
            }

            Section {
                TextField("Extra launch options", text: $model.launchArguments, prompt: Text("e.g. --use-d3d11"))
            } header: {
                Text("Launch")
            } footer: {
                Text("Passed to the game the same way as Steam's launch options.")
            }

            Section("Backups") {
                let backups = model.backups?.backups.sorted { $0.createdAt > $1.createdAt } ?? []
                if backups.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary)
                }
                ForEach(backups) { backup in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(backup.label + (backup.isOriginal ? " (original)" : ""))
                            Text("\(URL(fileURLWithPath: backup.originalPath).lastPathComponent) · \(backup.createdAt.formatted())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { model.perform { try model.backups?.restore(backup) } }
                    }
                }
            }

            Section("Support") {
                Button("Open Liberty Loader Folder") {
                    NSWorkspace.shared.open(model.supportDirectory)
                }
                if let log = LibertyLog.shared.fileURL {
                    Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private func chooseCrossOver() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard CrossOverLocator.inspect(url) != nil else {
            model.errorMessage = "That app doesn't look like CrossOver."
            return
        }
        model.crossOverPath = url.path
        model.refresh()
    }
}
