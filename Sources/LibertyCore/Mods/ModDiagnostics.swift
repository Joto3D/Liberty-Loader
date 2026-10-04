import Foundation

/// Explains why mods may not show up in game, using only files Liberty Loader can see.
public struct ModDiagnosis: Equatable, Identifiable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// The selected variant contains no patch files.
        case noPatchFiles
        /// These files should be in the game's data folder but aren't (never applied, or removed by Steam).
        case notDeployed(missing: [String])
        /// The game has no archive with this hash anymore: the mod was made for an older game version.
        case targetsMissingGameFile(hashes: [String])
        /// Mods lower in the load order change the same game files.
        case overriddenBy([String])
        case disabled
    }

    public let modID: UUID
    public let name: String
    public var problems: [Problem]

    public var id: UUID { modID }
    public var isOK: Bool { problems.isEmpty }
}

public struct DiagnosticsReport: Equatable, Sendable {
    public enum GlobalIssue: Equatable, Sendable {
        case gameUpdatedSinceDeploy
        case gameRunning
        /// Mods are enabled but nothing has ever been copied into the game.
        case nothingDeployed
        /// Patch files in the data folder that Liberty Loader didn't put there.
        case foreignPatchFiles(count: Int)
        /// A shared mod loader is enabled, but it wrote no log during the last game session.
        case loaderDidNotRun(name: String)
    }

    public var mods: [ModDiagnosis]
    public var global: [GlobalIssue]
    /// Logs written by mod loaders in the bottle, newest first.
    public var logs: [ModLogFile] = []

    /// Problems that mean "the game won't see this mod", worth surfacing right after applying.
    public var hasBlockingProblems: Bool {
        mods.contains { diagnosis in
            diagnosis.problems.contains {
                switch $0 {
                case .notDeployed, .targetsMissingGameFile, .noPatchFiles: return true
                case .overriddenBy, .disabled: return false
                }
            }
        }
    }
}

public enum ModDiagnostics {
    public static func run(store: ModStore, deployer: PatchDeployer, buildChanged: Bool, gameRunning: Bool) -> DiagnosticsReport {
        let fm = FileManager.default
        let dataDir = deployer.dataDir
        let enabled = store.mods.filter(\.enabled)
        let resolved = enabled.map(store.resolve)
        let plan = deployer.plan(for: resolved)
        let managed = Set(deployer.managedFiles())

        // For each archive hash, the mods touching it in load order.
        var modsByHash: [String: [UUID]] = [:]
        for copy in plan.copies {
            guard let modID = copy.modID else { continue }
            if modsByHash[copy.hash]?.last != modID { modsByHash[copy.hash, default: []].append(modID) }
        }
        let names = Dictionary(store.mods.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        var diagnoses: [ModDiagnosis] = []
        for mod in store.mods {
            guard mod.enabled else {
                diagnoses.append(ModDiagnosis(modID: mod.id, name: mod.name, problems: [.disabled]))
                continue
            }
            var problems: [ModDiagnosis.Problem] = []
            let patchSets = resolved.first { $0.id == mod.id }?.patchSets ?? []
            if patchSets.isEmpty {
                problems.append(.noPatchFiles)
            } else {
                let hashes = Array(Set(patchSets.map(\.hash))).sorted()
                let missingArchives = hashes.filter { !fm.fileExists(atPath: dataDir.appendingPathComponent($0).path) }
                if !missingArchives.isEmpty { problems.append(.targetsMissingGameFile(hashes: missingArchives)) }

                let expected = plan.copies.filter { $0.modID == mod.id }.map(\.destinationName)
                let missing = expected.filter {
                    !managed.contains($0) || !fm.fileExists(atPath: dataDir.appendingPathComponent($0).path)
                }
                if !missing.isEmpty { problems.append(.notDeployed(missing: missing.sorted())) }

                var laterMods: [String] = []
                for hash in hashes {
                    guard let order = modsByHash[hash], let index = order.firstIndex(of: mod.id) else { continue }
                    for other in order[(index + 1)...] {
                        if let name = names[other], !laterMods.contains(name) { laterMods.append(name) }
                    }
                }
                if !laterMods.isEmpty { problems.append(.overriddenBy(laterMods)) }
            }
            diagnoses.append(ModDiagnosis(modID: mod.id, name: mod.name, problems: problems))
        }

        var global: [DiagnosticsReport.GlobalIssue] = []
        if gameRunning { global.append(.gameRunning) }
        if buildChanged { global.append(.gameUpdatedSinceDeploy) }
        if !enabled.isEmpty && managed.isEmpty { global.append(.nothingDeployed) }
        let existing = (try? fm.contentsOfDirectory(atPath: dataDir.path)) ?? []
        let foreign = existing.filter { PatchSet.parse(fileName: $0) != nil && !managed.contains($0) }.count
        if foreign > 0 { global.append(.foreignPatchFiles(count: foreign)) }

        return DiagnosticsReport(mods: diagnoses, global: global)
    }
}
