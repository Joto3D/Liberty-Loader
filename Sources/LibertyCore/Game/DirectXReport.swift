import Foundation

/// Everything that decides whether Helldivers 2 runs on DirectX 12 or falls back to DirectX 11.
public struct DirectXReport: Equatable, Sendable {
    public enum Finding: Equatable, Sendable {
        case launchArgumentsForceDX11
        case steamForcesDX11(user: String)
        case dllDisabled(name: String, source: String)
        case backendWithoutDX12(String)
        case noCauseFound
    }

    public struct Override: Equatable, Sendable {
        public let name: String
        public let value: String
        public let source: String
    }

    public var choice: DirectXVersion
    public var launchArguments: [String]
    public var steamLaunchOptions: [(user: String, options: String)]
    public var overrides: [Override]
    public var graphicsBackend: String?
    public var rendererSettings: [(key: String, value: String)]
    public var findings: [Finding]

    public static func == (lhs: DirectXReport, rhs: DirectXReport) -> Bool { lhs.text == rhs.text }

    static let directXDLLs: Set<String> = ["d3d11", "d3d12", "d3d12core", "dxgi", "dxcore"]

    public static func collect(game: GamePaths, extraArguments: String, choice: DirectXVersion) -> DirectXReport {
        var report = DirectXReport(
            choice: choice,
            launchArguments: choice.launchArguments(extra: extraArguments),
            steamLaunchOptions: [],
            overrides: [],
            graphicsBackend: nil,
            rendererSettings: [],
            findings: []
        )

        let userdata = game.steamRootURL.appendingPathComponent("userdata")
        let users = (try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? []
        for user in users.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let url = user.appendingPathComponent("config/localconfig.vdf")
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let options = SteamLaunchOptions.launchOptions(appID: GamePaths.steamAppID, in: text) else { continue }
            report.steamLaunchOptions.append((user.lastPathComponent, options))
        }

        let registryKeys = [
            "Software\\Wine\\DllOverrides",
            "Software\\Wine\\AppDefaults\\helldivers2.exe\\DllOverrides",
        ]
        for file in ["user.reg", "system.reg"] {
            guard let registry = try? WineRegistryFile.load(from: game.bottleURL.appendingPathComponent(file)) else { continue }
            for key in registryKeys {
                for (name, value) in registry.values(in: key) where isDirectXDLL(name) {
                    report.overrides.append(Override(name: name, value: value, source: "\(file) [\(key)]"))
                }
            }
        }

        if let config = try? BottleConfig.load(from: game.bottleConfigURL) {
            report.graphicsBackend = config.value("CX_GRAPHICS_BACKEND", in: BottleConfig.environmentSection)
            if let env = config.value("WINEDLLOVERRIDES", in: BottleConfig.environmentSection) {
                for (name, value) in parseDLLOverrides(env) where isDirectXDLL(name) {
                    report.overrides.append(Override(name: name, value: value, source: "cxbottle.conf WINEDLLOVERRIDES"))
                }
            }
        }

        if let settings = try? UserSettingsConfig.load(from: game.userSettingsURL) {
            let hints = ["d3d", "dx", "render_api", "renderer", "graphics_api"]
            report.rendererSettings = settings.entries
                .filter { entry in hints.contains { entry.key.lowercased().contains($0) } }
                .map { ($0.key, $0.value) }
        }

        report.findings = findings(for: report)
        return report
    }

    static func isDirectXDLL(_ name: String) -> Bool {
        directXDLLs.contains(name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "*")))
    }

    /// Parses `WINEDLLOVERRIDES`, e.g. `d3d12=;dxgi,d3d11=n,b`.
    public static func parseDLLOverrides(_ value: String) -> [(String, String)] {
        value.split(separator: ";").flatMap { part -> [(String, String)] in
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let mode = pieces.count > 1 ? String(pieces[1]) : ""
            return pieces[0].split(separator: ",").map { (String($0).trimmingCharacters(in: .whitespaces), mode) }
        }
    }

    /// Wine treats an empty override value as "disabled".
    static func disables(_ value: String) -> Bool {
        let v = value.lowercased().trimmingCharacters(in: .whitespaces)
        return v.isEmpty || v == "d" || v == "disabled"
    }

    static func findings(for report: DirectXReport) -> [Finding] {
        var result: [Finding] = []
        if report.launchArguments.contains(where: { DirectXMode.forcesDX11($0) }) {
            result.append(.launchArgumentsForceDX11)
        }
        for entry in report.steamLaunchOptions where DirectXMode.forcesDX11(entry.options) {
            result.append(.steamForcesDX11(user: entry.user))
        }
        for override in report.overrides where disables(override.value) {
            let name = override.name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == "d3d12" || name == "d3d12core" || name == "dxgi" {
                result.append(.dllDisabled(name: override.name, source: override.source))
            }
        }
        if let backend = report.graphicsBackend?.lowercased(), backend == "dxvk" || backend == "wined3d" {
            result.append(.backendWithoutDX12(backend))
        }
        if result.isEmpty && report.choice == .dx12 { result = [.noCauseFound] }
        return result
    }

    /// Plain text to paste into a chat or bug report.
    public var text: String {
        var lines = ["Liberty Loader DirectX report", "Choice: \(choice == .dx12 ? "DirectX 12" : "DirectX 11")"]
        lines.append("Launch arguments: " + (launchArguments.isEmpty ? "(none)" : launchArguments.joined(separator: " ")))
        lines.append("Graphics backend: " + (graphicsBackend ?? "(default)"))
        if steamLaunchOptions.isEmpty {
            lines.append("Steam launch options: (none)")
        } else {
            for entry in steamLaunchOptions { lines.append("Steam launch options [\(entry.user)]: \(entry.options)") }
        }
        if overrides.isEmpty {
            lines.append("DirectX DLL overrides: (none)")
        } else {
            for o in overrides { lines.append("Override \(o.name)=\"\(o.value)\" in \(o.source)") }
        }
        for setting in rendererSettings { lines.append("user_settings.config: \(setting.key) = \(setting.value)") }
        lines.append("Findings: " + findings.map(Self.describe).joined(separator: "; "))
        return lines.joined(separator: "\n")
    }

    static func describe(_ finding: Finding) -> String {
        switch finding {
        case .launchArgumentsForceDX11: return "launch arguments force DX11"
        case .steamForcesDX11(let user): return "Steam launch options force DX11 (user \(user))"
        case .dllDisabled(let name, let source): return "\(name) disabled in \(source)"
        case .backendWithoutDX12(let backend): return "backend \(backend) has no DX12"
        case .noCauseFound: return "no cause found"
        }
    }
}
