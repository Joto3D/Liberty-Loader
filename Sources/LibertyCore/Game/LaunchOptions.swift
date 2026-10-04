import Foundation

/// Reads the Helldivers 2 launch options Steam stores inside the bottle.
public enum SteamLaunchOptions {
    /// `LaunchOptions` of app 553850 from the first `userdata/*/config/localconfig.vdf` that has them.
    public static func read(steamRoot: URL) -> String? {
        let userdata = steamRoot.appendingPathComponent("userdata")
        let users = (try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? []
        for user in users.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let url = user.appendingPathComponent("config/localconfig.vdf")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let options = launchOptions(appID: GamePaths.steamAppID, in: text) { return options }
        }
        return nil
    }

    /// Finds `apps/<appID>/LaunchOptions`, respecting nesting so other apps' options are ignored.
    public static func launchOptions(appID: String, in text: String) -> String? {
        var path: [String] = []
        var pendingKey: String?
        for token in tokens(in: text) {
            switch token {
            case .open:
                path.append(pendingKey ?? "")
                pendingKey = nil
            case .close:
                if !path.isEmpty { path.removeLast() }
                pendingKey = nil
            case .string(let value):
                if let key = pendingKey {
                    let count = path.count
                    if key.caseInsensitiveCompare("LaunchOptions") == .orderedSame, count >= 2,
                       path[count - 1] == appID, path[count - 2].caseInsensitiveCompare("apps") == .orderedSame {
                        return value
                    }
                    pendingKey = nil
                } else {
                    pendingKey = value
                }
            }
        }
        return nil
    }

    private enum Token { case open, close, string(String) }

    private static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            switch char {
            case "{": result.append(.open)
            case "}": result.append(.close)
            case "\"":
                var value = ""
                while let next = iterator.next(), next != "\"" {
                    if next == "\\", let escaped = iterator.next() {
                        value.append(escaped == "n" ? "\n" : escaped == "t" ? "\t" : escaped)
                    } else {
                        value.append(next)
                    }
                }
                result.append(.string(value))
            default: continue
            }
        }
        return result
    }
}

/// Whether Helldivers 2 is forced onto DirectX 11 (it defaults to DirectX 12).
public enum DirectXMode {
    public enum Source: Equatable, Sendable { case liberty, steam }

    static let dx11Flags: Set<String> = ["--use-d3d11", "-use-d3d11", "-dx11", "--dx11", "dx11"]

    public static func forcesDX11(_ args: String) -> Bool {
        args.split(whereSeparator: \.isWhitespace).contains { dx11Flags.contains($0.lowercased()) }
    }

    /// Where DirectX 11 is forced from, or nil if the game runs its DirectX 12 default.
    public static func dx11Source(libertyArgs: String, steamArgs: String?) -> Source? {
        if forcesDX11(libertyArgs) { return .liberty }
        if let steamArgs, forcesDX11(steamArgs) { return .steam }
        return nil
    }

    public static func removingDX11(from args: String) -> String {
        args.split(whereSeparator: \.isWhitespace)
            .filter { !dx11Flags.contains($0.lowercased()) }
            .joined(separator: " ")
    }
}

/// The DirectX version Liberty Loader starts the game with.
public enum DirectXVersion: String, CaseIterable, Identifiable, Sendable {
    /// The game's default; needed for DLSS/MetalFX.
    case dx12
    /// Often steadier under CrossOver; passes `--use-d3d11`.
    case dx11

    public var id: String { rawValue }

    /// The user's extra launch options with any DirectX 11 flag replaced by this choice.
    public func launchArguments(extra: String) -> [String] {
        let base = DirectXMode.removingDX11(from: extra).split(separator: " ").map(String.init)
        return self == .dx11 ? base + ["--use-d3d11"] : base
    }
}
