import AppKit
import LibertyCore
import SwiftUI

/// Explains per mod why it may not show up in game, with one-click fixes.
@MainActor
struct ModDiagnosisView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var report: DiagnosticsReport? { model.diagnostics }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let report {
                        ForEach(Array(report.global.enumerated()), id: \.offset) { _, issue in
                            globalBanner(issue)
                        }
                        if report.mods.isEmpty {
                            Text("No mods installed.").foregroundStyle(Color.hdMuted)
                        }
                        ForEach(report.mods) { diagnosis in
                            DiagnosisRow(diagnosis: diagnosis)
                        }
                        HDPanel {
                            Label {
                                Text("Everything looks right but mods still don't show? Start the game from Liberty Loader, or press Apply Now after starting it through Steam.")
                                    .foregroundStyle(Color.hdMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "lightbulb.fill").foregroundStyle(Color.hdYellow)
                            }
                        }
                    } else {
                        Text("Helldivers 2 was not found, so mods can't be checked.").foregroundStyle(Color.hdMuted)
                    }
                }
                .padding(20)
            }
            footer
        }
        .frame(width: 680, height: 620)
        .background(Color.hdBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mod Diagnosis")
                .font(.hdDisplay(30))
                .textCase(.uppercase)
                .foregroundStyle(Color.hdText)
            Text("Checks every mod against your game folder and explains what's wrong.")
                .foregroundStyle(Color.hdMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hdPanel)
        .overlay(alignment: .bottom) { HazardStripe().frame(height: 5).clipShape(Rectangle()) }
    }

    private var footer: some View {
        HStack {
            if let report {
                let broken = report.mods.filter { !$0.isOK && $0.problems != [.disabled] }.count
                if broken == 0 && report.global.isEmpty {
                    StatusPill(color: .hdSuccess, text: "All mods look good")
                } else {
                    StatusPill(color: .hdWarning, text: "Problems found")
                }
            }
            Spacer()
            if !model.allMissingRequirements().isEmpty {
                Button {
                    Task { await model.autoInstallMissingRequirements(force: true) }
                } label: {
                    Label("Install All Missing", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(HDPrimaryButtonStyle())
                .disabled(model.isAutoInstalling)
            }
            if !model.nexusAPIKey.isEmpty {
                Button {
                    Task { await model.refreshRequirements() }
                } label: {
                    Label("Check Requirements", systemImage: "link")
                }
                .buttonStyle(HDSecondaryButtonStyle())
                .help("Asks Nexus Mods which other mods your mods need.")
            }
            Button {
                model.runDiagnostics()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(HDSecondaryButtonStyle())
            Button("Done") { dismiss() }
                .buttonStyle(HDPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Color.hdPanel)
    }

    @ViewBuilder
    private func globalBanner(_ issue: DiagnosticsReport.GlobalIssue) -> some View {
        switch issue {
        case .gameRunning:
            HDBanner(icon: "play.circle.fill", color: .hdWarning,
                     title: Text("Helldivers 2 is running"),
                     message: Text("Mods are copied into the game when it starts. Quit the game, press Apply Now, then start it again from Liberty Loader."))
        case .gameUpdatedSinceDeploy:
            HDBanner(icon: "arrow.down.app.fill", color: .hdYellow,
                     title: Text("Helldivers 2 was updated"),
                     message: Text("Game updates often break mods. Mods marked “outdated” below need a new version from their author."))
        case .nothingDeployed:
            HDBanner(icon: "tray.and.arrow.down.fill", color: .hdDanger,
                     title: Text("Mods were never copied into the game"),
                     message: Text("This happens when the game is started through Steam instead of Liberty Loader.")) {
                Button("Apply Now", action: model.applyAndRediagnose)
                    .buttonStyle(HDPrimaryButtonStyle())
                    .disabled(model.isGameRunning)
            }
        case .foreignPatchFiles(let count):
            HDBanner(icon: "questionmark.folder.fill", color: .hdInfo,
                     title: Text("\(count) patch files from another tool"),
                     message: Text("Files in the game folder that Liberty Loader didn't install (for example from another mod manager or a manual install). They can override or break your mods. Liberty Loader never deletes them; remove them by hand if you don't need them.")) {
                Button("Show Game Folder") {
                    if let dir = model.game?.dataDir { NSWorkspace.shared.open(dir) }
                }
                .buttonStyle(HDSecondaryButtonStyle())
            }
        }
    }
}

@MainActor
struct DiagnosisRow: View {
    @Environment(AppModel.self) private var model
    let diagnosis: ModDiagnosis

    private var mod: InstalledMod? { model.findMod(diagnosis.modID) }
    private var missingRequirements: [NexusRequirement] { mod.map(model.missingRequirements(for:)) ?? [] }
    private var isDisabledOnly: Bool { diagnosis.problems == [.disabled] }
    private var isHealthy: Bool { diagnosis.isOK && missingRequirements.isEmpty }

    var body: some View {
        HDPanel(accent: isHealthy ? .hdSuccess : (isDisabledOnly ? nil : .hdWarning), padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isHealthy ? "checkmark.circle.fill" : (isDisabledOnly ? "pause.circle.fill" : "exclamationmark.triangle.fill"))
                        .foregroundStyle(isHealthy ? Color.hdSuccess : (isDisabledOnly ? Color.hdMuted : Color.hdWarning))
                    Text(verbatim: diagnosis.name).font(.headline).foregroundStyle(Color.hdText)
                    Spacer()
                    if isHealthy { HDTag(text: "OK", color: .hdSuccess) }
                }
                ForEach(Array(diagnosis.problems.enumerated()), id: \.offset) { _, problem in
                    problemLine(problem)
                }
                ForEach(missingRequirements, id: \.self) { requirement in
                    requirementLine(requirement)
                }
                if let mod, mod.nexusModID != nil, mod.requirements == nil {
                    Button("Check requirements on Nexus") {
                        if let id = mod.nexusModID,
                           let url = URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(id)?tab=description") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.hdYellow)
                }
            }
        }
    }

    @ViewBuilder
    private func problemLine(_ problem: ModDiagnosis.Problem) -> some View {
        switch problem {
        case .disabled:
            line("This mod is turned off.") {
                Button("Turn On") {
                    if var mod { mod.enabled = true; model.update(mod); model.runDiagnostics() }
                }
            }
        case .noPatchFiles:
            line("The selected variant contains no mod files. Pick another variant on the Mods page.") { EmptyView() }
        case .notDeployed(let missing):
            line("\(missing.count) files are not in the game folder yet.") {
                Button("Apply Now", action: model.applyAndRediagnose).disabled(model.isGameRunning)
            }
        case .targetsMissingGameFile:
            line("Outdated: the game no longer has the file this mod changes. Look for an updated version of the mod.") {
                if let id = mod?.nexusModID,
                   let url = URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(id)?tab=files") {
                    Button("Open on Nexus Mods") { NSWorkspace.shared.open(url) }
                }
                Button("Turn Off") { model.disable(diagnosis.modID) }
            }
        case .overriddenBy(let others):
            let names = others.joined(separator: ", ")
            line("Overlaps with \(names), which load later and win where both change the same thing.") {
                Button("Move to Bottom") { model.moveToBottom(diagnosis.modID) }
            }
        }
    }

    private func requirementLine(_ requirement: NexusRequirement) -> some View {
        let name = requirement.name
        return line("Needs “\(name)”, which isn't installed.") {
            Button(requirement.isExternal ? LocalizedStringKey("Open") : LocalizedStringKey("Install")) {
                Task { await model.installRequirement(requirement) }
            }
        }
    }

    private func line<Actions: View>(_ text: LocalizedStringKey, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.hdText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 6) { actions() }
                .buttonStyle(HDSecondaryButtonStyle())
        }
    }
}
