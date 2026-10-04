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
    @State private var retinaEnabled: Bool?
    @State private var showSavePreset = false
    @State private var newPresetName = ""
    @State private var showAdvanced = false

    private var allPresets: [PerformancePreset] { PerformancePreset.all + model.customPresets }

    private var recommended: PerformancePreset {
        PerformancePreset.recommended(cpuBrand: SystemInfo.cpuBrand, memoryBytes: SystemInfo.memoryBytes)
    }

    private var selectedPreset: PerformancePreset? {
        allPresets.first { $0.id == selectedPresetID }
    }

    var body: some View {
        HDPage {
            HDPageTitle(
                title: "Performance",
                subtitle: "Detected \(SystemInfo.cpuBrand), \(Int(SystemInfo.memoryBytes / 1_073_741_824)) GB memory. A backup is taken before every change."
            )
            StatusBanner()
            presetsSection
            bottleSection
            tipsSection
            advancedSection
        }
        .navigationTitle("Performance")
        .onAppear(perform: load)
        .onChange(of: model.game) { load() }
        .alert("Save Preset", isPresented: $showSavePreset) {
            TextField("Name, e.g. My Settings", text: $newPresetName)
            Button("Save") {
                model.saveCustomPreset(named: newPresetName, config: config ?? UserSettingsConfig(text: ""), bottle: bottleConfig)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves your current game and bottle settings so you can switch back to them later.")
        }
    }

    // MARK: Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HDSectionHeader(title: "Presets")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(allPresets) { preset in
                    PresetTile(
                        preset: preset,
                        isSelected: preset.id == selectedPresetID,
                        isRecommended: preset.id == recommended.id
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) { selectedPresetID = preset.id }
                    }
                }
            }
            if let preset = selectedPreset {
                HStack(spacing: 10) {
                    Button {
                        apply(preset)
                    } label: {
                        Label { Text("Apply \(Self.title(of: preset))") } icon: { Image(systemName: "bolt.fill") }
                    }
                    .buttonStyle(HDPrimaryButtonStyle())
                    .disabled(model.game == nil || model.isGameRunning)
                    Button("Restore Original Settings", action: restoreOriginal)
                        .buttonStyle(HDSecondaryButtonStyle())
                        .disabled(model.game == nil)
                    Spacer()
                    Button("Save Current as Preset…") {
                        newPresetName = ""
                        showSavePreset = true
                    }
                    .buttonStyle(HDSecondaryButtonStyle())
                    .disabled(config == nil)
                    if !preset.isBuiltIn {
                        Button("Delete", role: .destructive) {
                            model.deleteCustomPreset(preset)
                            selectedPresetID = recommended.id
                        }
                        .buttonStyle(HDSecondaryButtonStyle(color: .hdDanger))
                    }
                }
            }
            if !skippedKeys.isEmpty {
                let skipped = skippedKeys.joined(separator: ", ")
                HDBanner(
                    icon: "info.circle.fill",
                    color: .hdWarning,
                    title: Text("Some settings were skipped"),
                    message: Text("Not in your config: \(skipped). Launch the game once and change a graphics option to create a complete config.")
                )
            }
        }
    }

    /// Built-in presets are translated; custom preset names are shown as typed.
    static func title(of preset: PerformancePreset) -> Text {
        preset.isBuiltIn ? Text(LocalizedStringKey(preset.name)) : Text(verbatim: preset.name)
    }

    static func summary(of preset: PerformancePreset) -> Text {
        preset.isBuiltIn ? Text(LocalizedStringKey(preset.summary)) : Text("Your saved settings.")
    }

    // MARK: Bottle

    private var bottleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HDSectionHeader(title: "CrossOver bottle")
            HDPanel {
                if let bottleConfig {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingRow(icon: "cpu", title: "Graphics backend", detail: "D3DMetal is usually fastest on Apple Silicon.") {
                            Picker("", selection: Binding(
                                get: { bottleConfig.graphicsBackend ?? .d3dmetal },
                                set: { value in editBottle { $0.graphicsBackend = value } }
                            )) {
                                ForEach(BottleConfig.GraphicsBackend.allCases) { backend in
                                    Text(LocalizedStringKey(backend.displayName)).tag(backend)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                        Divider().overlay(Color.hdBorder)
                        SettingRow(icon: "arrow.triangle.branch", title: "MSync", detail: "Faster thread synchronisation.") {
                            toggle(bottleConfig.msyncEnabled) { value in editBottle { $0.msyncEnabled = value } }
                        }
                        SettingRow(icon: "arrow.triangle.swap", title: "ESync", detail: "Fallback if MSync is unstable.") {
                            toggle(bottleConfig.esyncEnabled) { value in editBottle { $0.esyncEnabled = value } }
                        }
                        SettingRow(icon: "gauge.with.dots.needle.67percent", title: "Metal FPS overlay", detail: "Shows FPS and frame times in the game.") {
                            toggle(bottleConfig.metalHUDEnabled) { value in editBottle { $0.metalHUDEnabled = value } }
                        }
                        if let retinaEnabled {
                            Divider().overlay(Color.hdBorder)
                            SettingRow(
                                icon: "display",
                                title: "High Resolution (Retina) Mode",
                                detail: model.isBottleBusy
                                    ? "Quit the game and Steam (or use Force Quit Bottle) to change this."
                                    : "Off gives much higher FPS. On looks sharper but renders 4× the pixels."
                            ) {
                                toggle(retinaEnabled, action: setRetina)
                                    .disabled(model.isBottleBusy)
                            }
                        }
                    }
                } else {
                    Text("No bottle selected.").foregroundStyle(Color.hdMuted)
                }
            }
        }
    }

    private func toggle(_ value: Bool, action: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value }, set: action))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(.hdYellow)
    }

    // MARK: Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HDSectionHeader(title: "Field manual")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                TipCard(icon: "rectangle.inset.filled", text: "Play in fullscreen so macOS Game Mode turns on (more CPU/GPU priority).")
                TipCard(icon: "display", text: "Keep High Resolution Mode off. Rendering at Retina resolution costs a lot of FPS.")
                TipCard(icon: "bolt.fill", text: "Plug in your MacBook and set Energy Mode to High Power where available.")
                TipCard(icon: "memorychip", text: "Quit browsers and other heavy apps. Helldivers 2 benefits from free unified memory.")
                TipCard(icon: "hourglass", text: "The first missions after an update stutter while shaders compile. This improves on its own.")
            }
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HDSectionHeader(
                    title: "All game settings",
                    trailing: AnyView(
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showAdvanced ? 0 : -90))
                            .foregroundStyle(Color.hdMuted)
                    )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                HDPanel {
                    if let config {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Filter", text: $filter)
                                .textFieldStyle(.roundedBorder)
                            ForEach(config.entries.filter { filter.isEmpty || $0.key.localizedCaseInsensitiveContains(filter) }) { entry in
                                HStack {
                                    Text(verbatim: entry.key)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(Color.hdText)
                                    Spacer()
                                    TextField("", text: Binding(
                                        get: { entry.value },
                                        set: { value in self.config?.set(entry.key, to: value) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 180)
                                    .multilineTextAlignment(.trailing)
                                }
                            }
                            Button("Save Settings", action: saveAdvanced)
                                .buttonStyle(HDPrimaryButtonStyle())
                                .disabled(model.isGameRunning)
                                .padding(.top, 6)
                        }
                    } else {
                        Text("user_settings.config not found. Launch Helldivers 2 once to create it.")
                            .foregroundStyle(Color.hdMuted)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard let game = model.game else { config = nil; bottleConfig = nil; retinaEnabled = nil; return }
        config = try? UserSettingsConfig.load(from: game.userSettingsURL)
        bottleConfig = (try? BottleConfig.load(from: game.bottleConfigURL)) ?? BottleConfig(text: "")
        retinaEnabled = (try? WineRegistryFile.load(from: game.userRegistryURL)).map { RetinaMode.isEnabled(in: $0) }
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
                if let esync = preset.esync { $0.esyncEnabled = esync }
                if let metalHUD = preset.metalHUD { $0.metalHUDEnabled = metalHUD }
            }
            let name = preset.isBuiltIn ? String(localized: String.LocalizationValue(preset.name)) : preset.name
            model.statusMessage = String(localized: "\(name) applied. Restart the game if it is running.")
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

    private func setRetina(_ enabled: Bool) {
        guard let game = model.game, !model.isBottleBusy else { return }
        model.perform {
            var registry = try WineRegistryFile.load(from: game.userRegistryURL)
            try model.backups?.backup(game.userRegistryURL, label: "Retina mode")
            RetinaMode.set(enabled, in: &registry)
            try registry.write(to: game.userRegistryURL)
            retinaEnabled = enabled
            model.statusMessage = enabled
                ? String(localized: "High Resolution Mode turned on.")
                : String(localized: "High Resolution Mode turned off.")
        }
    }

    private func saveAdvanced() {
        guard let game = model.game, let config else { return }
        model.perform {
            try model.backups?.backup(game.userSettingsURL, label: "Manual edit")
            try config.write(to: game.userSettingsURL)
            model.statusMessage = String(localized: "Game settings saved.")
        }
    }

    private func restoreOriginal() {
        guard let game = model.game, let backups = model.backups else { return }
        model.perform {
            // The registry is rewritten by Wine on exit, so only restore it while the bottle is idle.
            let files = [game.userSettingsURL, game.bottleConfigURL] + (model.isBottleBusy ? [] : [game.userRegistryURL])
            for file in files where backups.original(for: file) != nil {
                try backups.restoreOriginal(of: file)
            }
            model.statusMessage = String(localized: "Original settings restored.")
        }
        load()
    }
}

@MainActor
struct PresetTile: View {
    let preset: PerformancePreset
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var icon: String {
        switch preset.id {
        case PerformancePreset.ultraLow.id: return "bolt.fill"
        case PerformancePreset.maxPerformance.id: return "hare.fill"
        case PerformancePreset.balanced.id: return "scalemass.fill"
        case PerformancePreset.quality.id: return "sparkles"
        default: return "slider.horizontal.3"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? Color.black : Color.hdYellow)
                        .frame(width: 34, height: 34)
                        .background(isSelected ? Color.hdYellow : Color.hdYellow.opacity(0.12), in: CutCornerShape(cut: 7))
                    Spacer()
                    if isRecommended { HDTag(text: "Recommended") }
                    if !preset.isBuiltIn { HDTag(text: "Custom", color: .hdInfo) }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.hdYellow)
                    }
                }
                PerformanceView.title(of: preset)
                    .font(.hdDisplay(20))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hdText)
                PerformanceView.summary(of: preset)
                    .font(.caption)
                    .foregroundStyle(Color.hdMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(isSelected ? Color.hdYellow.opacity(0.08) : Color.hdPanel, in: CutCornerShape())
            .overlay(
                CutCornerShape()
                    .stroke(isSelected ? Color.hdYellow : Color.white.opacity(isHovered ? 0.2 : 0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

@MainActor
struct SettingRow<Control: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.hdYellow)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.hdText)
                Text(detail).font(.caption).foregroundStyle(Color.hdMuted)
            }
            Spacer()
            control
        }
    }
}

@MainActor
struct TipCard: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.hdYellow)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.hdText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hdPanel, in: CutCornerShape(cut: 8))
        .overlay(CutCornerShape(cut: 8).stroke(Color.hdBorder, lineWidth: 1))
    }
}
