import Foundation

/// One Stingray patch inside a mod: `<hash>.patch_<n>` plus its optional
/// `.gpu_resources` and `.stream` siblings, which must keep the same index.
public struct PatchSet: Equatable, Sendable {
    public let hash: String
    public let index: Int
    /// Source files keyed by suffix ("" for the main file, ".gpu_resources", ".stream").
    public let files: [String: URL]

    public static let suffixes = ["", ".gpu_resources", ".stream"]

    /// Parses a file name like `9ba626afa44a3aa3.patch_0.gpu_resources`.
    public static func parse(fileName: String) -> (hash: String, index: Int, suffix: String)? {
        let pattern = "^([0-9a-fA-F]{16})\\.patch_([0-9]+)(\\.gpu_resources|\\.stream)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)),
              let hashRange = Range(match.range(at: 1), in: fileName),
              let indexRange = Range(match.range(at: 2), in: fileName),
              let index = Int(fileName[indexRange]) else { return nil }
        var suffix = ""
        if let suffixRange = Range(match.range(at: 3), in: fileName) { suffix = String(fileName[suffixRange]) }
        return (String(fileName[hashRange]).lowercased(), index, suffix)
    }

    /// Collects every patch set found (recursively) in the given directories.
    public static func collect(in directories: [URL]) -> [PatchSet] {
        let fm = FileManager.default
        var grouped: [String: (hash: String, index: Int, files: [String: URL])] = [:]
        for directory in directories {
            guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let url as URL in enumerator {
                guard let parsed = parse(fileName: url.lastPathComponent) else { continue }
                let key = "\(parsed.hash)#\(parsed.index)#\(url.deletingLastPathComponent().path)"
                var entry = grouped[key] ?? (parsed.hash, parsed.index, [:])
                entry.files[parsed.suffix] = url
                grouped[key] = entry
            }
        }
        return grouped.values
            .filter { $0.files[""] != nil }
            .map { PatchSet(hash: $0.hash, index: $0.index, files: $0.files) }
            .sorted { ($0.hash, $0.index, $0.files[""]!.path) < ($1.hash, $1.index, $1.files[""]!.path) }
    }
}
