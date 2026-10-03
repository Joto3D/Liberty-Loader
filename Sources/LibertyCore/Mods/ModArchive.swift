import Foundation

/// Unpacks mod downloads (.zip, .7z, .rar, .tar.*) or copies plain folders.
public enum ModArchive {
    public static let supportedExtensions = ["zip", "7z", "rar", "tar", "gz", "tgz", "xz"]

    public static func extract(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue {
            for item in try fm.contentsOfDirectory(atPath: source.path) {
                try fm.copyItem(at: source.appendingPathComponent(item), to: destination.appendingPathComponent(item))
            }
            return
        }

        let ext = source.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw LibertyError.unsupportedArchive(ext) }

        // macOS ships bsdtar (libarchive), which reads zip, 7z, rar and tarballs.
        let tool: (String, [String])
        #if os(macOS)
        tool = ("/usr/bin/bsdtar", ["-xf", source.path, "-C", destination.path])
        #else
        tool = ext == "zip"
            ? ("/usr/bin/unzip", ["-q", "-o", source.path, "-d", destination.path])
            : ("/usr/bin/tar", ["-xf", source.path, "-C", destination.path])
        #endif
        let result = try Shell.run(tool.0, tool.1)
        guard result.status == 0 else { throw LibertyError.archiveExtractionFailed(result.output) }
    }

    /// True when the folder holds a Windows program (.exe/.dll) instead of mod files,
    /// e.g. a Windows mod manager downloaded by mistake.
    public static func containsWindowsProgram(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in enumerator where ["exe", "dll"].contains(url.pathExtension.lowercased()) {
            return true
        }
        return false
    }

    /// Skips wrapper folders (`MyMod/MyMod/...`) and macOS junk so the mod root holds the manifest or patch files.
    public static func contentRoot(of directory: URL) -> URL {
        let fm = FileManager.default
        var current = directory
        while true {
            let items = ((try? fm.contentsOfDirectory(atPath: current.path)) ?? [])
                .filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
            guard items.count == 1 else { return current }
            let only = current.appendingPathComponent(items[0])
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: only.path, isDirectory: &isDir), isDir.boolValue else { return current }
            current = only
        }
    }
}
