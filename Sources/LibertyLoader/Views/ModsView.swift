import AppKit
import LibertyCore
import SwiftUI

@MainActor
struct ModsView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @State private var confirmPurge = false
    @State private var showSaveProfile = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(spacing: 0) {
            StatusBanner().padding([.horizontal, .top])
            ForEach(model.nexusDownloads, id: \.self) { label in
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(label)…")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            if model.mods.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(model.mods) { mod in
                            ModRow(mod: mod)
                        }
                        .onMove(perform: model.move)
                    } header: {
                        Text("Load order — mods lower in the list win when they change the same file. Drag to reorder.")
                    }
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.install(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .navigationTitle("Mods")
        .toolbar {
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No mods yet").font(.title2.bold())
            Text("Drop a mod .zip, .7z or .rar here, click Install Mod, or use “Mod Manager Download” on Nexus Mods.")
                .foregroundStyle(.secondary)
            Button("Install Mod…") { model.showImporter = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct ModRow: View {
    @Environment(AppModel.self) private var model
    let mod: InstalledMod

    private var manifest: ModManifest? { model.store?.manifest(for: mod) }

    private var conflictsWith: [String] {
        Array(Set(model.conflicts.values.filter { $0.contains(mod.name) }.flatMap { $0 })
            .subtracting([mod.name])).sorted()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModPreview(url: model.store?.previewImageURL(for: mod))
            Toggle("", isOn: Binding(
                get: { mod.enabled },
                set: { var m = mod; m.enabled = $0; model.update(m) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(mod.name).font(.headline)
                    if mod.enabled && !conflictsWith.isEmpty {
                        Label("Overlaps", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Changes the same game files as: \(conflictsWith.joined(separator: ", "))")
                    }
                    if mod.hasUpdate {
                        Button {
                            model.openNexusPage(mod)
                        } label: {
                            Label("Update \(mod.latestVersion ?? "")", systemImage: "arrow.down.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Opens the mod's files on Nexus Mods. Click “Mod Manager Download” there to update it here.")
                    }
                    if let version = mod.version {
                        Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let description = mod.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let manifest, !manifest.options.isEmpty { optionPickers(manifest) }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show in Finder") { model.revealModFolder(mod) }
            if mod.nexusModID != nil {
                Button("Open on Nexus Mods") { model.openNexusPage(mod) }
            }
            Button("Uninstall", role: .destructive) { model.uninstall(mod) }
        }
    }

    @ViewBuilder
    private func optionPickers(_ manifest: ModManifest) -> some View {
        let optionIndex = min(mod.selectedOption ?? 0, manifest.options.count - 1)
        HStack {
            Picker("Variant", selection: Binding(
                get: { optionIndex },
                set: { var m = mod; m.selectedOption = $0; m.selectedSubOption = 0; model.update(m) }
            )) {
                ForEach(manifest.options.indices, id: \.self) { i in
                    Text(manifest.options[i].name).tag(i)
                }
            }
            .frame(maxWidth: 260)

            let subOptions = manifest.options[optionIndex].subOptions
            if !subOptions.isEmpty {
                Picker("Style", selection: Binding(
                    get: { min(mod.selectedSubOption ?? 0, subOptions.count - 1) },
                    set: { var m = mod; m.selectedSubOption = $0; model.update(m) }
                )) {
                    ForEach(subOptions.indices, id: \.self) { i in
                        Text(subOptions[i].name).tag(i)
                    }
                }
                .frame(maxWidth: 220)
            }
        }
        .controlSize(.small)
    }
}

/// Small thumbnail from the mod's icon or Nexus preview image.
@MainActor
struct ModPreview: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
