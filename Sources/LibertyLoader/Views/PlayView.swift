import LibertyCore
import SwiftUI

@MainActor
struct PlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                StatusBanner()
                if let release = model.availableUpdate { appUpdateBanner(release) }
                if model.showStuckPrompt { stuckBanner }
                checklist
                if model.gameUpdatedSinceLastSync { updateWarning }
                launchControls
                playtimeBox
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Play")
        .toolbar {
            Button { model.refresh() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Helldivers 2").font(.largeTitle.bold())
            Text("For Super Earth — now on your Mac.").foregroundStyle(.secondary)
        }
    }

    private var checklist: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                CheckRow(
                    ok: model.crossOver != nil,
                    title: model.crossOver.map { "CrossOver \($0.version ?? "")" } ?? "CrossOver not found",
                    detail: crossOverDetail
                )
                CheckRow(
                    ok: model.game != nil,
                    title: model.game.map { "Found in bottle “\($0.bottleName)”" } ?? "Helldivers 2 not found",
                    detail: model.game == nil ? "Install Steam in a CrossOver bottle and download Helldivers 2." : nil
                )
                let enabled = model.mods.filter(\.enabled).count
                CheckRow(ok: true, title: "\(enabled) mod\(enabled == 1 ? "" : "s") enabled", detail: model.conflicts.isEmpty ? nil : "\(model.conflicts.count) file conflict(s) — later mods in the list win.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func appUpdateBanner(_ release: ReleaseInfo) -> some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Liberty Loader \(release.version.description) is available").bold()
                    if !release.notes.isEmpty {
                        Text(release.notes).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                    }
                    HStack {
                        Button(model.isInstallingUpdate ? "Installing…" : "Install and Restart") {
                            Task { await model.installUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isInstallingUpdate)
                        Button("Later") { model.availableUpdate = nil }
                    }
                }
                Spacer()
            }
            .padding(6)
        }
    }

    private var stuckBanner: some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: "hourglass.badge.plus").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Helldivers 2 hasn't started").bold()
                    Text("Steam or the bottle may be stuck. Liberty Loader can stop everything in the bottle and try again.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Force Quit and Retry", action: model.retryLaunch)
                            .buttonStyle(.borderedProminent)
                        Button("Keep Waiting") { model.showStuckPrompt = false }
                    }
                }
                Spacer()
            }
            .padding(6)
        }
    }

    private var playtimeBox: some View {
        GroupBox {
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Total playtime").font(.caption).foregroundStyle(.secondary)
                    Text(PlaytimeRecord.format(model.playtime.total())).font(.title3.bold())
                }
                VStack(alignment: .leading) {
                    Text("Sessions").font(.caption).foregroundStyle(.secondary)
                    Text("\(model.playtime.sessionCount)").font(.title3.bold())
                }
                if model.playtime.lastSessionSeconds > 0 {
                    VStack(alignment: .leading) {
                        Text("Last session").font(.caption).foregroundStyle(.secondary)
                        Text(PlaytimeRecord.format(model.playtime.lastSessionSeconds)).font(.title3.bold())
                    }
                }
                Spacer()
            }
            .padding(6)
        }
    }

    private var crossOverDetail: String? {
        guard let crossOver = model.crossOver else { return "Install CrossOver or set its path in Settings." }
        return crossOver.isSupportedVersion ? nil : "Version 24 or newer is recommended for Helldivers 2."
    }

    private var updateWarning: some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Helldivers 2 was updated").bold()
                    Text("Game updates often break mods and can cause crashes. Disable mods until their authors publish updates.")
                        .foregroundStyle(.secondary)
                    Button("Disable All Mods") {
                        model.setAllEnabled(false)
                        model.applyModsNow()
                    }
                }
            }
            .padding(6)
        }
    }

    private var launchControls: some View {
        HStack(spacing: 12) {
            Button(action: model.launch) {
                Label(model.isGameRunning ? "Running" : "Launch Helldivers 2", systemImage: "play.fill")
                    .font(.title3.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.crossOver == nil || model.game == nil || model.isGameRunning)

            Button("Force Quit Bottle", role: .destructive, action: model.forceQuit)
                .disabled(model.crossOver == nil || model.game == nil)
                .help("Stops the game, Steam and any stuck Wine processes in this bottle.")
        }
    }
}

@MainActor
struct CheckRow: View {
    let ok: Bool
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
