import AppKit
import LibertyCore
import SwiftUI

@main
@MainActor
struct LibertyLoaderApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        model.refresh()
        model.startMonitoring()
        if model.autoCheckUpdates {
            Task { await model.checkForUpdates(userInitiated: false) }
        }
    }

    var body: some Scene {
        Window("Liberty Loader", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
                .onOpenURL { model.handleOpenURL($0) }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Install Mod…") { model.showImporter = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await model.checkForUpdates(userInitiated: true) }
                }
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: model.isGameRunning ? "shield.lefthalf.filled" : "shield")
        }
    }
}

/// Quick actions in the macOS menu bar.
@MainActor
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.isGameRunning ? "Helldivers 2 is running" : "Helldivers 2 is not running")
        Text("Playtime: \(PlaytimeRecord.format(model.playtime.total()))")
        Divider()
        Button("Launch Helldivers 2", action: model.launch)
            .disabled(model.crossOver == nil || model.game == nil || model.isGameRunning)
        Button("Force Quit Bottle", action: model.forceQuit)
            .disabled(model.game == nil)
        if !model.profiles.isEmpty {
            Menu("Mod Profile") {
                ForEach(model.profiles) { profile in
                    Button(profile.name) { model.applyProfile(profile) }
                }
            }
        }
        Divider()
        Button("Open Liberty Loader") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if model.availableUpdate != nil {
            Button("Install Update…") { Task { await model.installUpdate() } }
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
