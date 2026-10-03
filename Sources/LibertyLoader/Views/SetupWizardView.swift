import AppKit
import Combine
import LibertyCore
import SwiftUI

/// First-run assistant: CrossOver → Steam bottle → Helldivers 2 → preset → Nexus key.
@MainActor
struct SetupWizardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var appliedPreset = false
    private let recheck = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var status: SetupStatus { model.setupStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, done: status.isDone(.crossOver), title: "Install CrossOver",
                         detail: status.crossOverInstalled && !status.crossOverSupported
                            ? "CrossOver is installed, but version 24 or newer is recommended for Helldivers 2."
                            : "CrossOver runs Windows games on your Mac. Version 24 or newer is needed.") {
                        Button(status.crossOverInstalled ? LocalizedStringKey("Open CrossOver") : LocalizedStringKey("Get CrossOver"), action: model.openCrossOver)
                            .buttonStyle(HDSecondaryButtonStyle())
                    }
                    step(2, done: status.isDone(.steamBottle), title: "Install Steam in a bottle",
                         detail: "In CrossOver, choose “Install a Windows Application”, search for Steam and install it. Then sign in to Steam.") {
                        Button("Open CrossOver", action: model.openCrossOver)
                            .buttonStyle(HDSecondaryButtonStyle())
                            .disabled(!status.crossOverInstalled)
                    }
                    step(3, done: status.isDone(.game), title: "Download Helldivers 2",
                         detail: "Liberty Loader can ask Steam in your bottle to install the game. The download runs in Steam.") {
                        Button("Install with Steam", action: model.installGameWithSteam)
                            .buttonStyle(HDSecondaryButtonStyle())
                            .disabled(status.steamBottle == nil || status.gameInstalled)
                    }
                    step(4, done: appliedPreset, title: "Pick a performance preset",
                         detail: "Recommended for your Mac. You can change it any time on the Performance page.") {
                        Button("Use Recommended") { applyRecommended() }
                            .buttonStyle(HDSecondaryButtonStyle())
                            .disabled(!status.gameInstalled || appliedPreset)
                    }
                    step(5, done: !model.nexusAPIKey.isEmpty, title: "Connect Nexus Mods (optional)",
                         detail: "Lets you browse and install mods inside Liberty Loader.") {
                        HStack {
                            SecureField("API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Button("Save") {
                                model.nexusAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                apiKey = ""
                            }
                            .buttonStyle(HDSecondaryButtonStyle())
                            .disabled(apiKey.isEmpty)
                        }
                    }
                }
                .padding(22)
            }
            footer
        }
        .frame(width: 640, height: 640)
        .background(Color.hdBackground)
        .preferredColorScheme(.dark)
        .onReceive(recheck) { _ in model.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome, Helldiver")
                .font(.hdDisplay(32))
                .textCase(.uppercase)
                .foregroundStyle(Color.hdText)
            Text("Let's get Helldivers 2 running on your Mac. Steps tick off automatically.")
                .foregroundStyle(Color.hdMuted)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.2, green: 0.17, blue: 0.04), .hdPanel], startPoint: .topTrailing, endPoint: .bottomLeading))
        .overlay(alignment: .bottom) { HazardStripe().frame(height: 5).clipShape(Rectangle()) }
    }

    private var footer: some View {
        HStack {
            if status.isReady {
                StatusPill(color: .hdSuccess, text: "Ready to dive")
            } else {
                StatusPill(color: .hdYellow, text: "Setup in progress")
            }
            Spacer()
            Button(status.isReady ? LocalizedStringKey("Done") : LocalizedStringKey("Skip for Now")) {
                model.setupSeen = true
                dismiss()
            }
            .buttonStyle(HDPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
        .background(Color.hdPanel)
    }

    private func step<Action: View>(
        _ number: Int,
        done: Bool,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let isCurrent = !done && (SetupStep(rawValue: number - 1) == status.currentStep)
        return HDPanel(accent: done ? .hdSuccess : (isCurrent ? .hdYellow : nil)) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .black))
                    } else {
                        Text(verbatim: "\(number)").font(.hdDisplay(18))
                    }
                }
                .foregroundStyle(done ? Color.black : (isCurrent ? Color.black : Color.hdMuted))
                .frame(width: 30, height: 30)
                .background(done ? Color.hdSuccess : (isCurrent ? Color.hdYellow : Color.white.opacity(0.08)), in: CutCornerShape(cut: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Color.hdText)
                    Text(detail).font(.callout).foregroundStyle(Color.hdMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    action().padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .opacity(done ? 0.75 : 1)
        }
    }

    private func applyRecommended() {
        guard let game = model.game else { return }
        let preset = PerformancePreset.recommended(cpuBrand: SystemInfo.cpuBrand, memoryBytes: SystemInfo.memoryBytes)
        model.perform {
            if var config = try? UserSettingsConfig.load(from: game.userSettingsURL) {
                try model.backups?.backup(game.userSettingsURL, label: "Setup assistant")
                _ = config.apply(preset.gameSettings)
                try config.write(to: game.userSettingsURL)
            }
            var bottle = (try? BottleConfig.load(from: game.bottleConfigURL)) ?? BottleConfig(text: "")
            try model.backups?.backup(game.bottleConfigURL, label: "Setup assistant")
            bottle.graphicsBackend = preset.graphicsBackend
            bottle.msyncEnabled = preset.msync
            try bottle.write(to: game.bottleConfigURL)
        }
        appliedPreset = true
    }
}
