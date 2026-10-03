import LibertyCore
import SwiftUI

@MainActor
struct PerformanceView: View {
    @Environment(AppModel.self) private var model

    @State private var config: UserSettingsConfig?
    @State private var bottleConfig: BottleConfig?
    @State private var selectedPresetID = PerformancePreset.recommended(
        cpuBrand: SystemInfo.cpuBrand, memoryBytes: SystemInfo.memoryBytes
    ).id
    @State private var skippedKeys: [String] = []
    @State private var filter = ""

    private var recommended: PerformancePreset {
        PerformancePreset.recommended(cpuBrand: SystemInfo.cpuBrand, memoryBytes: SystemInfo.memoryBytes)
    }

    var body: some View {
        Form {
            StatusBanner()
            presetsSection
            bottleSection
            tipsSection
            advancedSection
        }
        .formStyle(.grouped)
        .navigationTitle("Performance")
        .onAppear(perform: load)
        .onChange(of: model.game) { load() }
    }

    // MARK: Sections

    private var presetsSection: some View {
        Section {
            Picker("Preset", selection: $selectedPresetID) {
                ForEach(PerformancePreset.all) { preset in
                    Text(preset.id == recommended.id ? "\(preset.name) (recommended)" : preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.segmented)
            if let preset = PerformancePreset.all.first(where: { $0.id == selectedPresetID }) {
                Text(preset.summary).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Apply \(preset.name)") { apply(preset) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.game == nil || model.isGameRunning)
                    Button("Restore Original Settings", action: restoreOriginal)
                        .disabled(model.game == nil)
                }
            }
            if !skippedKeys.isEmpty {
                Text("Not in your config (skipped): \(skippedKeys.joined(separator: ", ")). Launch the game once and change a graphics option to create a complete config.")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("Detected \(SystemInfo.cpuBrand), \(SystemInfo.memoryBytes / 1_073_741_824) GB memory. A backup is taken before every change.")
        }
    }

    private var bottleSection: some View {
        Section("CrossOver Bottle") {
            if let bottleConfig {
                Picker("Graphics backend", selection: Binding(
                    get: { bottleConfig.graphicsBackend ?? .d3dmetal },
                    set: { value in editBottle { $0.graphicsBackend = value } }
                )) {
                    ForEach(BottleConfig.GraphicsBackend.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("MSync (faster thread synchronisation)", isOn: Binding(
                    get: { bottleConfig.msyncEnabled },
                    set: { value in editBottle { $0.msyncEnabled = value } }
                ))
                Toggle("ESync (fallback if MSync is unstable)", isOn: Binding(
                    get: { bottleConfig.esyncEnabled },
                    set: { value in editBottle { $0.esyncEnabled = value } }
                ))
                Toggle("Metal FPS overlay", isOn: Binding(
                    get: { bottleConfig.metalHUDEnabled },
                    set: { value in editBottle { $0.metalHUDEnabled = value } }
                ))
            } else {
                Text("No bottle selected.").foregroundStyle(.secondary)
            }
        }
    }

    private var tipsSection: some View {
        Section("Tips") {
            Label("Play in fullscreen so macOS Game Mode turns on (more CPU/GPU priority).", systemImage: "rectangle.inset.filled")
            Label("Turn off High Resolution Mode in the bottle's CrossOver settings — rendering at Retina resolution costs a lot of FPS.", systemImage: "display")
            Label("Plug in your MacBook and set Energy Mode to High Power where available.", systemImage: "bolt.fill")
            Label("Quit browsers and other heavy apps; Helldivers 2 benefits from free unified memory.", systemImage: "memorychip")
            Label("The first missions after an update stutter while shaders compile — this improves on its own.", systemImage: "hourglass")
        }
        .font(.callout)
    }

    private var advancedSection: some View {
        Section("All Game Settings (user_settings.config)") {
            if let config {
                TextField("Filter", text: $filter)
                ForEach(config.entries.filter { filter.isEmpty || $0.key.localizedCaseInsensitiveContains(filter) }) { entry in
                    HStack {
                        Text(entry.key).font(.system(.body, design: .monospaced))
                        Spacer()
                        TextField("", text: Binding(
                            get: { entry.value },
                            set: { value in self.config?.set(entry.key, to: value) }
                        ))
                        .frame(width: 180)
                        .multilineTextAlignment(.trailing)
                    }
                }
                Button("Save Settings", action: saveAdvanced)
                    .disabled(model.isGameRunning)
            } else {
                Text("user_settings.config not found. Launch Helldivers 2 once to create it.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard let game = model.game else { config = nil; bottleConfig = nil; return }
        config = try? UserSettingsConfig.load(from: game.userSettingsURL)
        bottleConfig = (try? BottleConfig.load(from: game.bottleConfigURL)) ?? BottleConfig(text: "")
    }

    private func apply(_ preset: PerformancePreset) {
        guard let game = model.game else { return }
        model.perform {
            if var config = try? UserSettingsConfig.load(from: game.userSettingsURL) {
                try model.backups?.backup(game.userSettingsURL, label: "Before \(preset.name)")
                skippedKeys = config.apply(preset.gameSettings)
                try config.write(to: game.userSettingsURL)
            }
            editBottle {
                $0.graphicsBackend = preset.graphicsBackend
                $0.msyncEnabled = preset.msync
            }
            model.statusMessage = "\(preset.name) applied. Restart the game if it is running."
        }
        load()
    }

    private func editBottle(_ change: (inout BottleConfig) -> Void) {
        guard let game = model.game, var updated = bottleConfig else { return }
        change(&updated)
        model.perform {
            try model.backups?.backup(game.bottleConfigURL, label: "Bottle settings")
            try updated.write(to: game.bottleConfigURL)
            bottleConfig = updated
        }
    }

    private func saveAdvanced() {
        guard let game = model.game, let config else { return }
        model.perform {
            try model.backups?.backup(game.userSettingsURL, label: "Manual edit")
            try config.write(to: game.userSettingsURL)
            model.statusMessage = "Game settings saved."
        }
    }

    private func restoreOriginal() {
        guard let game = model.game, let backups = model.backups else { return }
        model.perform {
            for file in [game.userSettingsURL, game.bottleConfigURL] where backups.original(for: file) != nil {
                try backups.restoreOriginal(of: file)
            }
            model.statusMessage = "Original settings restored."
        }
        load()
    }
}
