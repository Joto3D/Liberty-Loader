import LibertyCore
import SwiftUI

@MainActor
struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem

    var body: some View {
        HDPage {
            StatusBanner()
            hero
            if let release = model.availableUpdate { appUpdateBanner(release) }
            if model.showStuckPrompt { stuckBanner }
            if model.gameUpdatedSinceLastSync { gameUpdateBanner }
            stats
            checklist
        }
        .navigationTitle("Play")
        .toolbar {
            Button { model.refresh() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.17, blue: 0.04), Color.hdPanel, Color.hdBackground],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 240, weight: .black))
                .foregroundStyle(Color.hdYellow.opacity(0.07))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
                .offset(y: 30)

            VStack(alignment: .leading, spacing: 10) {
                Text("For Super Earth")
                    .font(.hdLabel(12))
                    .tracking(3)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hdYellow)
                Text(verbatim: "HELLDIVERS 2")
                    .font(.hdDisplay(56))
                    .foregroundStyle(Color.hdText)
                Text("Mods, performance and launch, managed for your Mac.")
                    .foregroundStyle(Color.hdMuted)
                HStack(spacing: 12) {
                    Button(action: model.launch) {
                        Label(model.isGameRunning ? LocalizedStringKey("Deployed") : LocalizedStringKey("Launch"), systemImage: model.isGameRunning ? "checkmark" : "play.fill")
                    }
                    .buttonStyle(HDPrimaryButtonStyle(large: true))
                    .disabled(model.crossOver == nil || model.game == nil || model.isGameRunning)
                    .keyboardShortcut(.return, modifiers: .command)

                    Button(action: model.forceQuit) {
                        Label("Force Quit Bottle", systemImage: "xmark.octagon")
                    }
                    .buttonStyle(HDSecondaryButtonStyle(color: .hdDanger))
                    .disabled(model.crossOver == nil || model.game == nil)
                    .help("Stops the game, Steam and any stuck Wine processes in this bottle.")
                }
                .padding(.top, 8)
            }
            .padding(28)
        }
        .frame(height: 290)
        .clipShape(CutCornerShape(cut: 24))
        .overlay(CutCornerShape(cut: 24).stroke(Color.hdYellow.opacity(0.25), lineWidth: 1))
        .overlay(alignment: .bottom) {
            HazardStripe().frame(height: 6).clipShape(Rectangle())
        }
    }

    // MARK: Stats

    private var stats: some View {
        let enabled = model.mods.filter(\.enabled).count
        return HStack(spacing: 12) {
            StatTile(icon: "shippingbox.fill", label: "Mods active", value: "\(enabled) / \(model.mods.count)")
            StatTile(icon: "clock.fill", label: "Playtime", value: PlaytimeRecord.format(model.playtime.total()))
            StatTile(icon: "flag.fill", label: "Missions", value: "\(model.playtime.sessionCount)")
            StatTile(
                icon: "hourglass",
                label: "Last session",
                value: model.playtime.lastSessionSeconds > 0 ? PlaytimeRecord.format(model.playtime.lastSessionSeconds) : "–"
            )
        }
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            HDSectionHeader(title: "Pre-flight check")
            HDPanel {
                VStack(alignment: .leading, spacing: 14) {
                    CheckRow(
                        ok: model.crossOver != nil,
                        title: model.crossOver.map { Text("CrossOver \($0.version ?? "")") } ?? Text("CrossOver not found"),
                        detail: crossOverDetail
                    )
                    Divider().overlay(Color.hdBorder)
                    CheckRow(
                        ok: model.game != nil,
                        title: model.game.map { Text("Helldivers 2 found in bottle “\($0.bottleName)”") } ?? Text("Helldivers 2 not found"),
                        detail: model.game == nil ? Text("Install Steam in a CrossOver bottle and download Helldivers 2.") : nil
                    )
                    Divider().overlay(Color.hdBorder)
                    CheckRow(
                        ok: model.conflicts.isEmpty,
                        warning: !model.conflicts.isEmpty,
                        title: Text("\(model.mods.filter(\.enabled).count) mods enabled"),
                        detail: model.conflicts.isEmpty ? nil : Text("\(model.conflicts.count) file overlaps. Mods lower in the list win."),
                        action: reviewAction
                    )
                }
            }
        }
    }

    private var reviewAction: (LocalizedStringKey, () -> Void)? {
        guard !model.conflicts.isEmpty else { return nil }
        let binding = $selection
        return ("Review", { binding.wrappedValue = .mods })
    }

    private var crossOverDetail: Text? {
        guard let crossOver = model.crossOver else { return Text("Install CrossOver or set its path in Settings.") }
        return crossOver.isSupportedVersion ? nil : Text("Version 24 or newer is recommended for Helldivers 2.")
    }

    // MARK: Banners

    private func appUpdateBanner(_ release: ReleaseInfo) -> some View {
        HDBanner(
            icon: "arrow.down.circle.fill",
            color: .hdInfo,
            title: Text("Liberty Loader \(release.version.description) is available"),
            message: release.notes.isEmpty ? nil : Text(verbatim: release.notes)
        ) {
            Button {
                Task { await model.installUpdate() }
            } label: {
                Text(model.isInstallingUpdate ? LocalizedStringKey("Installing…") : LocalizedStringKey("Install and Restart"))
            }
            .buttonStyle(HDPrimaryButtonStyle())
            .disabled(model.isInstallingUpdate)
            Button("Later") { model.availableUpdate = nil }
                .buttonStyle(HDSecondaryButtonStyle())
        }
    }

    private var stuckBanner: some View {
        HDBanner(
            icon: "hourglass.badge.plus",
            color: .hdWarning,
            title: Text("Helldivers 2 hasn't started"),
            message: Text("Steam or the bottle may be stuck. Liberty Loader can stop everything in the bottle and try again.")
        ) {
            Button("Force Quit and Retry", action: model.retryLaunch)
                .buttonStyle(HDPrimaryButtonStyle())
            Button("Keep Waiting") { model.showStuckPrompt = false }
                .buttonStyle(HDSecondaryButtonStyle())
        }
    }

    private var gameUpdateBanner: some View {
        HDBanner(
            icon: "exclamationmark.triangle.fill",
            color: .hdYellow,
            title: Text("Helldivers 2 was updated"),
            message: Text("Game updates often break mods and can cause crashes. Disable mods until their authors publish updates.")
        ) {
            Button("Disable All Mods") {
                model.setAllEnabled(false)
                model.applyModsNow()
            }
            .buttonStyle(HDPrimaryButtonStyle())
        }
    }
}

@MainActor
struct CheckRow: View {
    let ok: Bool
    var warning = false
    let title: Text
    let detail: Text?
    var action: (LocalizedStringKey, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : (warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ok ? Color.hdSuccess : (warning ? Color.hdWarning : Color.hdDanger))
            VStack(alignment: .leading, spacing: 2) {
                title.foregroundStyle(Color.hdText)
                if let detail {
                    detail.font(.caption).foregroundStyle(Color.hdMuted)
                }
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(HDSecondaryButtonStyle())
            }
        }
    }
}
