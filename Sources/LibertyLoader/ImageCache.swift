import AppKit

/// Keeps decoded images in memory so scrolling never reads from disk or the network twice.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Local file images: loaded once, then served from memory.
    func image(at url: URL) -> NSImage? {
        if let image = cached(url) { return image }
        guard url.isFileURL, let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Remote images: downloaded once per app session.
    func load(_ url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        if url.isFileURL { return image(at: url) }
        guard let data = try? await URLSession.shared.data(from: url).0,
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
