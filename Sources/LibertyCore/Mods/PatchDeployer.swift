import Foundation

/// Copies enabled mods into `Helldivers 2/data`, renumbering patches so mods never overwrite each other.
///
/// The game loads `<hash>.patch_0`, `<hash>.patch_1`, ... and higher indices win, so mods are assigned
/// indices in load order. Every file we create is recorded, and only those files are ever removed.
public struct PatchDeployer {
    public struct Copy: Equatable {
        public let source: URL
        public let destinationName: String
        /// The mod this file belongs to, and the game archive it patches.
        public var modID: UUID? = nil
        public var hash: String = ""
    }

    public struct Plan: Equatable {
        public var copies: [Copy] = []
        /// Archive hash -> names of enabled mods that patch it (only when more than one).
        public var conflicts: [String: [String]] = [:]
    }

    struct Record: Codable {
        var files: [String]
    }

    public let dataDir: URL
    let recordURL: URL
    let guardrail: PathGuard

    /// - Parameter stateDirectory: where the list of deployed files is kept (Liberty Loader's support folder).
    public init(dataDir: URL, stateDirectory: URL) {
        self.dataDir = dataDir
        self.recordURL = stateDirectory.appendingPathComponent("deployed-\(Self.stableKey(for: dataDir)).json")
        self.guardrail = PathGuard(allowedRoots: [dataDir])
    }

    /// Files Liberty Loader placed in the data folder during the last sync.
    public func managedFiles() -> [String] {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return [] }
        return record.files
    }

    public func plan(for mods: [ResolvedMod]) -> Plan {
        let managed = Set(managedFiles())
        var nextIndex: [String: Int] = [:]

        // Patches we didn't create (other tools, manual installs) keep their slots.
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: dataDir.path)) ?? []
        for name in existing where !managed.contains(name) {
            if let parsed = PatchSet.parse(fileName: name) {
                nextIndex[parsed.hash] = max(nextIndex[parsed.hash] ?? 0, parsed.index + 1)
            }
        }

        var plan = Plan()
        var touchedBy: [String: [String]] = [:]
        for mod in mods {
            for patch in mod.patchSets {
                let index = nextIndex[patch.hash] ?? 0
                nextIndex[patch.hash] = index + 1
                for suffix in PatchSet.suffixes {
                    guard let source = patch.files[suffix] else { continue }
                    plan.copies.append(Copy(
                        source: source,
                        destinationName: "\(patch.hash).patch_\(index)\(suffix)",
                        modID: mod.id,
                        hash: patch.hash
                    ))
                }
                if touchedBy[patch.hash]?.last != mod.name {
                    touchedBy[patch.hash, default: []].append(mod.name)
                }
            }
        }
        plan.conflicts = touchedBy.filter { $0.value.count > 1 }
        return plan
    }

    /// Makes the data folder match `mods` exactly.
    @discardableResult
    public func sync(_ mods: [ResolvedMod]) throws -> Plan {
        let plan = plan(for: mods)
        try purge()
        let fm = FileManager.default
        var written: [String] = []
        defer { try? saveRecord(written) }
        for copy in plan.copies {
            let destination = dataDir.appendingPathComponent(copy.destinationName)
            try guardrail.check(destination)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: copy.source, to: destination)
            written.append(copy.destinationName)
        }
        LibertyLog.shared.info("Deployed \(written.count) mod files to \(dataDir.path)")
        return plan
    }

    /// Removes every file Liberty Loader deployed, leaving the game's own files untouched.
    public func purge() throws {
        let fm = FileManager.default
        for name in managedFiles() {
            let url = dataDir.appendingPathComponent(name)
            try guardrail.check(url)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
        try saveRecord([])
    }

    private func saveRecord(_ files: [String]) throws {
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Record(files: files)).write(to: recordURL, options: .atomic)
    }

    /// Deterministic, filesystem-safe key per data folder (FNV-1a; `hashValue` is randomized per launch).
    static func stableKey(for url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
