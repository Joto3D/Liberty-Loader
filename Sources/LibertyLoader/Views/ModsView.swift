import AppKit
import LibertyCore
import SwiftUI

enum ModFilter: CaseIterable, Identifiable {
    case all, enabled, updates, conflicts

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .enabled: return "Enabled"
        case .updates: return "Updates"
        case .conflicts: return "Overlaps"
        }
    }
}

@MainActor
struct ModsView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @State private var confirmPurge = false
    @State private var showSaveProfile = false
    @State private var newProfileName = ""
    @State private var search = ""
    @State private var filter: ModFilter = .all

    private var conflictingNames: Set<String> {
        Set(model.conflicts.values.flatMap { $0 })
    }

    private func matches(_ mod: InstalledMod, _ filter: ModFilter) -> Bool {
        switch filter {
        case .all: return true
        case .enabled: return mod.enabled
        case .updates: return mod.hasUpdate
        case .conflicts: return mod.enabled && conflictingNames.contains(mod.name)
        }
    }

    private var visibleMods: [InstalledMod] {
        model.mods.filter { mod in
            matches(mod, filter) && (search.isEmpty || mod.name.localizedCaseInsensitiveContains(search))
        }
    }

    /// Reordering only makes sense on the full, unfiltered list.
    private var canReorder: Bool { filter == .all && search.isEmpty }

    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard canReorder else { return nil }
        let model = model
        return { source, destination in model.move(from: source, to: destination) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HDPageTitle(title: "Mods", subtitle: "Drop mods here. Lower in the list wins when two mods change the same file.")
                StatusBanner()
                if model.diagnosticsHint {
                    HDBanner(
                        icon: "stethoscope",
                        color: .hdWarning,
                        title: Text("Some mods may not work"),
                        message: Text("Liberty Loader found problems that can keep mods from showing up in game.")
                    ) {
                        Button("Diagnose", action: model.openDiagnostics)
                            .buttonStyle(HDPrimaryButtonStyle())
                        Button("Dismiss") { model.diagnosticsHint = false }
                            .buttonStyle(HDSecondaryButtonStyle())
                    }
                }
                ForEach(model.nexusDownloads, id: \.self) { label in
                    HDPanel(accent: .hdInfo, padding: 12) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Downloading \(label)…").foregroundStyle(Color.hdText)
                        }
                    }
                }
                if !model.mods.isEmpty { filterBar }
            }
            .padding([.horizontal, .top], HDMetrics.pagePadding)

            if model.mods.isEmpty {
                emptyState
            } else if visibleMods.isEmpty {
                Text("No mods match.")
                    .foregroundStyle(Color.hdMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleMods) { mod in
                        ModRow(mod: mod, isConflicting: conflictingNames.contains(mod.name))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: HDMetrics.pagePadding - 8, bottom: 5, trailing: HDMetrics.pagePadding - 8))
                    }
                    .onMove(perform: moveAction)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.hdBackground)
        .overlay {
            if isDropTargeted {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 44, weight: .black))
                        Text("Drop to install").font(.hdDisplay(28)).textCase(.uppercase)
                    }
                    .foregroundStyle(Color.hdYellow)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.hdYellow, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .padding(10)
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            model.install(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .navigationTitle("Mods")
        .toolbar { toolbarContent }
        .sheet(item: Binding(
            get: { model.guideModID.map(GuideID.init) },
            set: { model.guideModID = $0?.id }
        )) { item in
            ModGuideSheet(modID: item.id).environment(model)
        }
        .sheet(isPresented: Binding(get: { model.showDiagnostics }, set: { model.showDiagnostics = $0 })) {
            ModDiagnosisView().environment(model)
        }
        .alert("Save Profile", isPresented: $showSaveProfile) {
            TextField("Name, e.g. Cosmetics only", text: $newProfileName)
            Button("Save") { model.saveProfile(named: newProfileName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves which mods are on, their order and chosen variants.")
        }
        .confirmationDialog("Remove all mod files from the game folder?", isPresented: $confirmPurge) {
            Button("Remove", role: .destructive, action: model.purgeMods)
        } message: {
            Text("Your mod library is kept. Only files Liberty Loader placed in the game folder are removed.")
        }
    }

    // MARK: Pieces

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.hdMuted)
                TextField("Search mods", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.hdMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 260)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

            ForEach(ModFilter.allCases) { item in
                let count = model.mods.filter { matches($0, item) }.count
                if item == .all || count > 0 {
                    HDChip(title: item.title, count: count, isSelected: filter == item) {
                        withAnimation(.easeOut(duration: 0.15)) { filter = item }
                    }
                }
            }
            Spacer()
            if !canReorder {
                Text("Clear filters to reorder")
                    .font(.caption)
                    .foregroundStyle(Color.hdMuted)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                CutCornerShape(cut: 20)
                    .stroke(Color.hdYellow.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .frame(width: 120, height: 120)
                Image(systemName: "shippingbox")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Color.hdYellow)
            }
            Text("No mods deployed yet")
                .font(.hdDisplay(26))
                .textCase(.uppercase)
                .foregroundStyle(Color.hdText)
            Text("Drop a .zip, .7z or .rar here, click Install Mod, or use “Mod Manager Download” on Nexus Mods.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.hdMuted)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button { model.showImporter = true } label: { Label("Install Mod", systemImage: "plus") }
                    .buttonStyle(HDPrimaryButtonStyle())
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.nexusmods.com/helldivers2/mods/")!)
                } label: {
                    Label("Browse Nexus Mods", systemImage: "safari")
                }
                .buttonStyle(HDSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.showImporter = true } label: { Label("Install Mod", systemImage: "plus") }
            Menu {
                ForEach(model.profiles) { profile in
                    Button(profile.name) { model.applyProfile(profile) }
                }
                if !model.profiles.isEmpty { Divider() }
                Button("Save Current Setup as Profile…") {
                    newProfileName = ""
                    showSaveProfile = true
                }
                if !model.profiles.isEmpty {
                    Menu("Delete Profile") {
                        ForEach(model.profiles) { profile in
                            Button(profile.name, role: .destructive) { model.deleteProfile(profile) }
                        }
                    }
                }
            } label: {
                Label("Profiles", systemImage: "person.2.crop.square.stack")
            }
            .help("Switch between saved mod setups.")
            Button {
                Task { await model.checkModUpdates() }
            } label: {
                Label("Check for Mod Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Checks Nexus Mods for newer versions of mods installed from there.")
            .disabled(model.isCheckingModUpdates || !model.mods.contains { $0.nexusModID != nil })
            Button(action: model.openDiagnostics) { Label("Diagnose", systemImage: "stethoscope") }
                .help("Checks why mods might not show up in game.")
                .disabled(model.game == nil || model.mods.isEmpty)
            Button(action: model.applyModsNow) { Label("Apply Now", systemImage: "arrow.down.doc") }
                .help("Copy enabled mods into the game folder (also done automatically on launch).")
                .disabled(model.game == nil || model.isGameRunning)
            Menu {
                Button("Enable All") { model.setAllEnabled(true) }
                Button("Disable All") { model.setAllEnabled(false) }
                Divider()
                Button("Remove All Mod Files From Game…", role: .destructive) { confirmPurge = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}

@MainActor
struct ModRow: View {
    @Environment(AppModel.self) private var model
    let mod: InstalledMod
    let isConflicting: Bool
    @State private var isHovered = false

    private var manifest: ModManifest? { model.manifestCache[mod.id] }

    private var conflictList: String { conflictsWith.joined(separator: ", ") }

    private var conflictsWith: [String] {
        Array(Set(model.conflicts.values.filter { $0.contains(mod.name) }.flatMap { $0 })
            .subtracting([mod.name])).sorted()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.hdMuted.opacity(isHovered ? 1 : 0.3))
            ModPreview(url: model.previewCache[mod.id])
                .opacity(mod.enabled ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(verbatim: mod.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(mod.enabled ? Color.hdText : Color.hdMuted)
                    if let version = mod.version {
                        Text(verbatim: "v\(version)").font(.hdLabel(10)).foregroundStyle(Color.hdMuted)
                    }
                    if mod.hasUpdate {
                        Button { model.openNexusPage(mod) } label: {
                            HDTag(text: "Update available", color: .hdInfo)
                        }
                        .buttonStyle(.plain)
                        .help("Opens the mod's files on Nexus Mods. Click “Mod Manager Download” there to update it here.")
                    }
                    if let pin = mod.loadOrderPin {
                        Group {
                            if pin == .bottom {
                                HDTag(text: "Pinned last", color: .hdYellow)
                            } else {
                                HDTag(text: "Pinned first", color: .hdYellow)
                            }
                        }
                        .help(mod.pinIsManual == true
                              ? Text("You pinned this mod. Right-click to change it.")
                              : Text("The mod's description asks for this position, so Liberty Loader keeps it there. Right-click to change it."))
                    }
                    ForEach(model.missingRequirements(for: mod), id: \.self) { requirement in
                        Button {
                            Task { await model.installRequirement(requirement) }
                        } label: {
                            HDTag(text: "Needs \(requirement.name)", color: .hdDanger)
                        }
                        .buttonStyle(.plain)
                        .help("This mod needs another mod. Click to install it.")
                    }
                    if mod.enabled && isConflicting {
                        HDTag(text: "Overlaps", color: .hdWarning)
                            .help(Text("Changes the same game files as: \(conflictList)"))
                    }
                }
                if let description = mod.description, !description.isEmpty {
                    Text(verbatim: description)
                        .font(.caption)
                        .foregroundStyle(Color.hdMuted)
                        .lineLimit(2)
                }
                if let manifest, !manifest.options.isEmpty { optionPickers(manifest) }
            }

            Spacer(minLength: 8)

            Button { model.showGuide(for: mod) } label: {
                Image(systemName: "book.fill")
                    .foregroundStyle(Color.hdYellow.opacity(isHovered ? 1 : 0.6))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Guide: how to use this mod")

            Toggle("", isOn: Binding(
                get: { mod.enabled },
                set: { value in
                    var m = mod
                    m.enabled = value
                    withAnimation(.easeOut(duration: 0.15)) { model.update(m) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(.hdYellow)
        }
        .padding(12)
        .background(mod.enabled ? Color.hdPanelRaised : Color.hdPanel, in: CutCornerShape(cut: 10))
        .overlay(
            CutCornerShape(cut: 10)
                .stroke(mod.enabled ? Color.hdYellow.opacity(isHovered ? 0.6 : 0.3) : Color.hdBorder, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { model.showGuide(for: mod) }
        .contextMenu {
            Button("Show Guide") { model.showGuide(for: mod) }
            Button("Show in Finder") { model.revealModFolder(mod) }
            Menu("Load Order") {
                Button("Keep at Bottom") { model.setPin(.bottom, for: mod.id) }
                Button("Keep at Top") { model.setPin(.top, for: mod.id) }
                Button("Don't Pin") { model.setPin(nil, for: mod.id) }
            }
            if mod.nexusModID != nil {
                Button("Open on Nexus Mods") { model.openNexusPage(mod) }
            }
            Divider()
            Button("Uninstall", role: .destructive) { model.uninstall(mod) }
        }
    }

    @ViewBuilder
    private func optionPickers(_ manifest: ModManifest) -> some View {
        let optionIndex = min(mod.selectedOption ?? 0, manifest.options.count - 1)
        HStack(spacing: 10) {
            Picker("Variant", selection: Binding(
                get: { optionIndex },
                set: { var m = mod; m.selectedOption = $0; m.selectedSubOption = 0; model.update(m) }
            )) {
                ForEach(manifest.options.indices, id: \.self) { i in
                    Text(verbatim: manifest.options[i].name).tag(i)
                }
            }
            .frame(maxWidth: 240)

            let subOptions = manifest.options[optionIndex].subOptions
            if !subOptions.isEmpty {
                Picker("Style", selection: Binding(
                    get: { min(mod.selectedSubOption ?? 0, subOptions.count - 1) },
                    set: { var m = mod; m.selectedSubOption = $0; model.update(m) }
                )) {
                    ForEach(subOptions.indices, id: \.self) { i in
                        Text(verbatim: subOptions[i].name).tag(i)
                    }
                }
                .frame(maxWidth: 200)
            }
        }
        .controlSize(.small)
    }
}

/// Thumbnail from the mod's icon or Nexus preview image.
@MainActor
struct ModPreview: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = ImageCache.shared.image(at: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.hdYellow.opacity(0.5))
            }
        }
        .frame(width: 64, height: 64)
        .background(Color.black.opacity(0.35))
        .clipShape(CutCornerShape(cut: 8))
    }
}

/// Identifiable wrapper so the guide sheet can use `.sheet(item:)`.
struct GuideID: Identifiable {
    let id: UUID
}
