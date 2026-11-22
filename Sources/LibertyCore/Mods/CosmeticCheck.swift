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

    /// A kind of game resource a mod's patches replace.
    ///
    /// This is read from the patch archives themselves, so it describes what a
    /// mod actually changes rather than what files happen to sit beside it. It
    /// is the difference between "no code found" and "replaces audio".
    public enum ResourceKind: String, CaseIterable, Equatable, Sendable, Codable {
        case audio, texture, material, mesh, animation, stateMachine, particles, bones, physics, strings

        public var displayName: String {
            switch self {
            case .stateMachine: return "state machines"
            default: return rawValue
            }
        }

        /// Changes what is drawn. This is where visibility advantages live —
        /// removed fog, high-contrast or transparent skins, thinner silhouettes.
        public var isVisual: Bool {
            switch self {
            case .texture, .material, .mesh, .particles: return true
            default: return false
            }
        }

        /// Governs behaviour rather than appearance.
        public var affectsBehaviour: Bool {
            switch self {
            case .stateMachine, .physics: return true
            default: return false
            }
        }
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
        /// Resource kinds this mod's patches replace, in a stable order.
        ///
        /// Empty when the patches carry no type hash this check recognises,
        /// which means "not identified", never "replaces nothing".
        public let replaces: [ResourceKind]

        public init(verdict: Verdict, signals: [Signal], patchFileCount: Int,
                    unrecognisedFileCount: Int, replaces: [ResourceKind] = []) {
            self.verdict = verdict
            self.signals = signals
            self.patchFileCount = patchFileCount
            self.unrecognisedFileCount = unrecognisedFileCount
            self.replaces = replaces
        }

        /// What this mod changes, for showing next to the verdict.
        ///
        /// Audio-only is the lowest-risk shape there is, because sound cannot
        /// change what a player sees. That is a statement about effect, not a
        /// promise of safety — this never claims a mod is allowed, only what it
        /// touches.
        public var replacesSummary: String {
            guard !replaces.isEmpty else {
                return patchFileCount == 0
                    ? String(localized: "no asset patches")
                    : String(localized: "contents not identified")
            }
            return replaces.map(\.displayName).joined(separator: ", ")
        }

        /// True when every identified resource is non-visual and non-behavioural.
        /// Useful for ordering a list, not for telling anyone they are safe.
        public var isAudioOnly: Bool {
            !replaces.isEmpty && replaces.allSatisfy { $0 == .audio }
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
        var patchPaths: [String] = []

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
                patchPaths.append(full)
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
        var found = Set<ResourceKind>()
        for path in patchPaths { found.formUnion(Self.resourceKinds(inPatchAt: path)) }
        let replaces = ResourceKind.allCases.filter { found.contains($0) }
        return Report(verdict: verdict, signals: signals, patchFileCount: patchCount,
                      unrecognisedFileCount: unrecognised, replaces: replaces)
    }

    // MARK: - Patch contents

    /// How much of each `.patch_<n>` is scanned.
    ///
    /// Do not "fix" this to read whole files. Measured on a real library of 57
    /// patch files (largest 86 MB), a 256 KiB cap gave results identical to
    /// scanning every byte on all 57: the type hashes live in the header
    /// region, and the bulk payload lives in the `.stream` / `.gpu_resources`
    /// siblings. Some patches are hundreds of megabytes, and this runs for
    /// every installed mod on each reload.
    static let patchScanLimit = 256 * 1024

    /// Stingray resource type hashes (8-byte little-endian) -> kind.
    private static let typeHashes: [UInt64: ResourceKind] = [
        0x504B55235D63CCCF: .audio,        // wwise_stream
        0x535A7BD3E650D799: .audio,        // wwise_bank
        0xCD4238C6A0C69E32: .texture,
        0xEAC0B497876ADEDF: .material,
        0xE0A48D0BE9A7453F: .mesh,         // unit
        0x931E336D7646CC26: .animation,
        0xA486D4045106165C: .stateMachine,
        0xA14E8DFA2CD117E2: .particles,
        0x18DEAD01056B72E9: .bones,
        0x5F7203C8F280DAB8: .physics,
        0x9831CA893B0D087D: .strings,
        0xAA5965F03029FA18: .strings,
    ]

    /// Reads at most `patchScanLimit` bytes and matches 8-byte-aligned words
    /// against the hash table. Unreadable or short files yield nothing.
    private static func resourceKinds(inPatchAt path: String) -> Set<ResourceKind> {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: patchScanLimit), data.count >= 8 else { return [] }
        var kinds = Set<ResourceKind>()
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset + 8 <= raw.count {
                let word = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                if let kind = typeHashes[word] { kinds.insert(kind) }
                offset += 8
            }
        }
        return kinds
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
