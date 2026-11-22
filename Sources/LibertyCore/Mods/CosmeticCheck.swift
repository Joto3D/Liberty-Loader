import Foundation

/// Inspects a mod and reports whether it ships anything that can run code.
///
/// ## What this can and cannot tell you
///
/// It can tell you a mod ships a native binary, a script, or a declared
/// dependency on the code-loader stack. Those are positive findings: when one
/// is present, the mod is not purely cosmetic.
///
/// It **cannot** tell you a mod is safe. Helldivers 2 asset patches are opaque
/// containers — a `.patch_0` holds engine resources this check does not open,
/// and asset replacement alone can change gameplay-relevant things such as
/// model silhouettes or whether an effect renders. So the absence of findings
/// means "nothing that runs code was found", never "this mod is harmless".
///
/// Every piece of user-facing text built from a report must preserve that
/// distinction. `Verdict.assetsOnly` is deliberately not called `safe`.
public struct CosmeticCheck: Sendable {

    public enum Verdict: String, Equatable, Sendable, Codable {
        /// Only asset patches and metadata were found. Not a safety guarantee.
        case assetsOnly
        /// Something that executes was found: a binary, a script, or a declared
        /// dependency on a runtime that patches the game in memory.
        case runsCode
        /// Nothing recognisable either way — an empty folder, or a layout this
        /// check does not understand. Report it honestly rather than guessing.
        case inconclusive
    }

    /// One reason a mod was judged to run code.
    public struct Signal: Equatable, Sendable, Codable {
        public enum Kind: String, Equatable, Sendable, Codable {
            /// A loadable binary: .dll, .exe, .so, .dylib, …
            case nativeCode
            /// An interpreted script: .lua, .py, .js, .sh, .bat, …
            case script
            /// Declares or ships the code-loader stack (Bingus, HD2Runtime),
            /// which exists precisely to patch the running game.
            case runtimeDependency
            /// A plain file carrying the executable bit.
            case executableBit
        }

        public let kind: Kind
        /// Path relative to the mod folder, for showing the user.
        public let path: String
        /// Short human explanation, e.g. "requires HD2Runtime".
        public let detail: String

        public init(kind: Kind, path: String, detail: String) {
            self.kind = kind
            self.path = path
            self.detail = detail
        }
    }

    public struct Report: Equatable, Sendable, Codable {
        public let verdict: Verdict
        /// Every reason found, in a stable order. Empty when `assetsOnly`.
        public let signals: [Signal]
        /// How many `.patch_*` files the mod ships.
        public let patchFileCount: Int
        /// Files the check did not recognise as either assets or code.
        public let unrecognisedFileCount: Int

        public init(verdict: Verdict, signals: [Signal], patchFileCount: Int, unrecognisedFileCount: Int) {
            self.verdict = verdict
            self.signals = signals
            self.patchFileCount = patchFileCount
            self.unrecognisedFileCount = unrecognisedFileCount
        }

        /// A one-line summary. Phrased so it never promises safety.
        public var summary: String {
            switch verdict {
            case .assetsOnly:
                return "No code found — \(patchFileCount) asset patch\(patchFileCount == 1 ? "" : "es"). Asset mods can still change what you see."
            case .runsCode:
                let kinds = Set(signals.map(\.kind))
                if kinds.contains(.runtimeDependency) {
                    return "Runs code: needs a mod runtime that patches the game while it runs."
                }
                return "Runs code: ships \(signals.count) executable file\(signals.count == 1 ? "" : "s")."
            case .inconclusive:
                return "Couldn't tell — no asset patches and nothing executable found."
            }
        }
    }

    public init() {}

    /// Walks a mod folder and reports what it finds.
    ///
    /// Never throws and never follows symlinks out of the folder. An
    /// unreadable folder is `.inconclusive`, not a crash.
    public func inspect(modDirectory: URL) -> Report {
        let fm = FileManager.default
        let root = modDirectory.path
        guard (try? fm.contentsOfDirectory(atPath: root)) != nil else {
            return Report(verdict: .inconclusive, signals: [], patchFileCount: 0, unrecognisedFileCount: 0)
        }

        var signals: [Signal] = []
        var patchCount = 0
        var unrecognised = 0

        // Top-level runtime/mod directories holding at least one file.
        let topLevel = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        for name in topLevel.sorted() {
            let lower = name.lowercased()
            guard lower == "runtime" || lower == "mod" else { continue }
            let full = (root as NSString).appendingPathComponent(name)
            guard Self.fileType(fm, full) == .typeDirectory, Self.containsRegularFile(fm, full) else { continue }
            signals.append(Signal(kind: .runtimeDependency, path: name,
                                  detail: "ships a top-level \"\(name)\" folder with files in it"))
        }

        func walk(_ relDir: String) {
            let fullDir = relDir.isEmpty ? root : (root as NSString).appendingPathComponent(relDir)
            guard let names = try? fm.contentsOfDirectory(atPath: fullDir) else { return }
            for name in names {
                let rel = relDir.isEmpty ? name : relDir + "/" + name
                let full = (fullDir as NSString).appendingPathComponent(name)
                let type = Self.fileType(fm, full)
                if type == .typeDirectory { walk(rel); continue }
                guard type == .typeRegular else { continue } // symlinks and specials are skipped
                classify(rel: rel, name: name, full: full)
            }
        }

        func classify(rel: String, name: String, full: String) {
            let lower = name.lowercased()
            let ext = (lower as NSString).pathExtension
            var reported = false

            if Self.nativeExtensions.contains(ext) {
                signals.append(Signal(kind: .nativeCode, path: rel, detail: "native code (.\(ext))"))
                reported = true
            } else if Self.scriptExtensions.contains(ext) {
                signals.append(Signal(kind: .script, path: rel, detail: "script (.\(ext))"))
                reported = true
            }

            let isManifest = lower == "manifest.json" || lower.hasSuffix("-manifest.json")
            var runtimeDetail: String?
            if isManifest { runtimeDetail = Self.requiredRuntime(in: full) }
            if runtimeDetail == nil {
                if lower == "hd2runtime.json" {
                    runtimeDetail = "HD2Runtime configuration file"
                } else if lower.contains("bingus") {
                    runtimeDetail = "file named for the Bingus loader"
                }
            }
            if let detail = runtimeDetail {
                signals.append(Signal(kind: .runtimeDependency, path: rel, detail: detail))
                reported = true
            }

            if !reported,
               let attrs = try? FileManager.default.attributesOfItem(atPath: full),
               let perms = attrs[.posixPermissions] as? NSNumber,
               perms.intValue & 0o111 != 0 {
                signals.append(Signal(kind: .executableBit, path: rel, detail: "file has the executable bit set"))
                reported = true
            }

            if Self.isPatchFile(lower) {
                patchCount += 1
            } else if Self.isPatchSibling(lower) || Self.assetExtensions.contains(ext) {
                // asset or metadata: not a signal, not unrecognised
            } else if !reported {
                unrecognised += 1
            }
        }

        walk("")

        let order: [Signal.Kind] = [.nativeCode, .script, .runtimeDependency, .executableBit]
        signals.sort {
            let a = order.firstIndex(of: $0.kind) ?? 0, b = order.firstIndex(of: $1.kind) ?? 0
            return a != b ? a < b : $0.path < $1.path
        }

        let verdict: Verdict = !signals.isEmpty ? .runsCode : (patchCount > 0 ? .assetsOnly : .inconclusive)
        return Report(verdict: verdict, signals: signals, patchFileCount: patchCount, unrecognisedFileCount: unrecognised)
    }

    // MARK: - Classification tables

    private static let nativeExtensions: Set<String> =
        ["dll", "exe", "so", "dylib", "bundle", "framework", "a", "o", "sys", "ocx"]
    private static let scriptExtensions: Set<String> =
        ["lua", "py", "pyc", "js", "mjs", "cjs", "ts", "sh", "bash", "zsh", "command", "bat", "cmd",
         "ps1", "vbs", "jar", "rb", "pl", "applescript", "scpt"]
    private static let assetExtensions: Set<String> =
        // Images.
        ["png", "jpg", "jpeg", "webp", "gif", "bmp", "tga", "dds",
         // Audio. Sound and voice replacements are the commonest cosmetic mods
         // here, and they ship loose source audio beside their patches; without
         // these every one of them looks full of unrecognised files.
         "wav", "ogg", "mp3", "flac", "aiff", "aif", "m4a", "wem",
         // Metadata and documentation.
         "txt", "md", "json", "cfg", "ini", "toml", "yml", "yaml", "strings",
         "pdf", "rtf", "url", "webloc"]

    /// `<name>.patch_<n>` (lowercased input).
    private static func isPatchFile(_ lower: String) -> Bool {
        guard let r = lower.range(of: ".patch_", options: .backwards) else { return false }
        let digits = lower[r.upperBound...]
        return !digits.isEmpty && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }

    /// `<name>.patch_<n>.stream` / `.gpu_resources` (lowercased input).
    private static func isPatchSibling(_ lower: String) -> Bool {
        for suffix in [".stream", ".gpu_resources"] where lower.hasSuffix(suffix) {
            return isPatchFile(String(lower.dropLast(suffix.count)))
        }
        return false
    }

    private static func fileType(_ fm: FileManager, _ path: String) -> FileAttributeType? {
        // attributesOfItem does not follow symlinks.
        (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
    }

    private static func containsRegularFile(_ fm: FileManager, _ dir: String) -> Bool {
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return false }
        for n in names {
            let p = (dir as NSString).appendingPathComponent(n)
            switch fileType(fm, p) {
            case .typeRegular: return true
            case .typeDirectory: if containsRegularFile(fm, p) { return true }
            default: break
            }
        }
        return false
    }

    /// If a manifest's `requires` object names Bingus or HD2Runtime, describes it.
    private static func requiredRuntime(in path: String) -> String? {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber,
              size.intValue <= 1_000_000,
              let data = fm.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requires = obj["requires"] as? [String: Any] else { return nil }
        for key in requires.keys.sorted() {
            let lower = key.lowercased()
            guard lower.contains("bingus") || lower.contains("hd2runtime") else { continue }
            let pretty = lower.contains("hd2runtime") ? "HD2Runtime" : key
            var version: String?
            if let s = requires[key] as? String {
                version = s
            } else if let d = requires[key] as? [String: Any] {
                for k in ["version", "minVersion", "min_version", "min"] {
                    if let s = d[k] as? String { version = s; break }
                }
            }
            if let v = version, !v.isEmpty { return "requires \(pretty) \(v)" }
            return "requires \(pretty)"
        }
        return nil
    }
}
