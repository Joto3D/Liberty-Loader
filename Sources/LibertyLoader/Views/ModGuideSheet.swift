import AppKit
import LibertyCore
import SwiftUI

/// Everything a mod says about itself: how to use it, full description, variants and readme.
@MainActor
struct ModGuideSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let modID: UUID
    @State private var isLoading = false
    @State private var showReadme = false
    @State private var readme: String?

    private var mod: InstalledMod? { model.findMod(modID) }
    private var manifest: ModManifest? { model.manifestCache[modID] }

    /// All description sources, de-duplicated, best first.
    private var descriptions: [String] {
        guard let mod else { return [] }
        let candidates = [
            mod.nexusDescription.map(NexusText.plainText(fromBBCode:)),
            manifest?.description,
            mod.description,
        ]
        var result: [String] = []
        for case let text? in candidates {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(where: { $0.contains(trimmed) }) else { continue }
            result.append(trimmed)
        }
        return result
    }

    private var highlights: [String] {
        let optionTexts = (manifest?.options ?? []).flatMap { [$0.description] + $0.subOptions.map(\.description) }.compactMap { $0 }
        return ModGuide.instructionHighlights(in: (descriptions + [readme ?? ""] + optionTexts).joined(separator: "\n\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    howToUse
                    if !descriptions.isEmpty { descriptionSection }
                    if let manifest, !manifest.options.isEmpty { variantsSection(manifest) }
                    if let readme { readmeSection(readme) }
                }
                .padding(20)
            }
            footer
        }
        .frame(width: 640, height: 640)
        .background(Color.hdBackground)
        .preferredColorScheme(.dark)
        .task {
            readme = mod.flatMap { model.store?.readmeText(for: $0) }
            if mod?.nexusModID != nil && mod?.nexusDescription == nil {
                isLoading = true
                await model.loadNexusDescription(for: modID)
                isLoading = false
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            ModPreview(url: model.previewCache[modID])
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: mod?.name ?? "")
                    .font(.hdDisplay(26))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hdText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let version = mod?.version { Text(verbatim: "v\(version)").font(.hdLabel(11)).foregroundStyle(Color.hdMuted) }
                    if mod?.enabled == true {
                        StatusPill(color: .hdSuccess, text: "Enabled")
                    } else {
                        StatusPill(color: .hdMuted, text: "Off")
                    }
                    if mod?.loadOrderPin == .bottom { HDTag(text: "Pinned last") }
                    if mod?.loadOrderPin == .top { HDTag(text: "Pinned first") }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Color.hdPanel)
        .overlay(alignment: .bottom) { HazardStripe().frame(height: 5).clipShape(Rectangle()) }
    }

    private var howToUse: some View {
        VStack(alignment: .leading, spacing: 10) {
            HDSectionHeader(title: "How to use")
            HDPanel(accent: .hdYellow) {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoading && highlights.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text("Loading the description from Nexus Mods…").foregroundStyle(Color.hdMuted) }
                    } else if highlights.isEmpty {
                        Text("This mod doesn't describe special controls. Most mods work automatically once applied: start the game from Liberty Loader.")
                            .foregroundStyle(Color.hdMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(highlights, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "chevron.right.2").font(.caption.bold()).foregroundStyle(Color.hdYellow)
                                Text(verbatim: line)
                                    .foregroundStyle(Color.hdText)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HDSectionHeader(title: "Description")
            HDPanel {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(descriptions, id: \.self) { text in
                        Text(verbatim: text)
                            .font(.callout)
                            .foregroundStyle(Color.hdText.opacity(0.88))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func variantsSection(_ manifest: ModManifest) -> some View {
        let selected = mod?.selectedOption ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HDSectionHeader(title: "Variants")
            HDPanel {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(manifest.options.indices, id: \.self) { i in
                        let option = manifest.options[i]
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: i == selected ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(i == selected ? Color.hdYellow : Color.hdMuted)
                                Text(verbatim: option.name).foregroundStyle(Color.hdText)
                            }
                            if let description = option.description, !description.isEmpty {
                                Text(verbatim: description).font(.caption).foregroundStyle(Color.hdMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 22)
                            }
                            if !option.subOptions.isEmpty {
                                Text(verbatim: option.subOptions.map(\.name).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Color.hdMuted)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                    Text("Change the variant in the mod list on the Mods page.")
                        .font(.caption).foregroundStyle(Color.hdMuted)
                }
            }
        }
    }

    private func readmeSection(_ readme: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showReadme.toggle() }
            } label: {
                HDSectionHeader(
                    title: "Readme",
                    trailing: AnyView(Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showReadme ? 0 : -90))
                        .foregroundStyle(Color.hdMuted))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showReadme {
                HDPanel {
                    Text(verbatim: readme)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.hdText.opacity(0.85))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let id = mod?.nexusModID,
               let url = URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(id)?tab=description") {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open on Nexus Mods", systemImage: "safari") }
                    .buttonStyle(HDSecondaryButtonStyle())
            }
            if let mod {
                Button { model.revealModFolder(mod) } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(HDSecondaryButtonStyle())
            }
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(HDPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Color.hdPanel)
    }
}
