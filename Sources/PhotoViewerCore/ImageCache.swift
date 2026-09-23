import Foundation
import Darwin

/// Identify file contents using fresh size, modification time, and inode metadata.
/// ctime deliberately does not participate: Finder tags/last-opened attributes change
/// it without changing the image, and must not invalidate preloaded pixels.
public struct ImageFileVersion: Equatable {
    private let device: Int32
    private let inode: UInt64
    private let size: Int64
    private let modifiedSeconds: Int
    private let modifiedNanos: Int

    public init?(url: URL) {
        var info = stat()
        guard url.isFileURL, stat(url.path, &info) == 0 else { return nil }
        device = info.st_dev; inode = info.st_ino; size = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
    }
}

/// Owned by the main thread. Background decoders hand completed images back to it.
public final class ImageCache {
    private struct Entry {
        let image: DecodedImage
        let version: ImageFileVersion
        let cost: Int
    }
    public let byteLimit: Int
    public private(set) var totalCost = 0
    public var count: Int { entries.count }
    private var entries: [URL: Entry] = [:]
    private var priority: [URL] = []

    public init(byteLimit: Int = 256 * 1024 * 1024) { self.byteLimit = max(0, byteLimit) }

    /// Current image first, then nearby images in decreasing priority.
    public func setPriority(_ urls: [URL]) {
        var seen = Set<URL>()
        priority = urls.filter { seen.insert($0).inserted }
        trim()
    }

    public func image(for url: URL) -> DecodedImage? {
        guard let entry = entries[url] else { return nil }
        guard ImageFileVersion(url: url) == entry.version else { remove(url); return nil }
        return entry.image
    }

    public func insert(_ image: DecodedImage, for url: URL, version: ImageFileVersion) {
        // A file replaced during decoding must never become a valid cache entry.
        guard priority.contains(url), ImageFileVersion(url: url) == version else { return }
        remove(url)
        let cost = image.image.bytesPerRow * image.image.height + max(0, image.fileSize)
        guard cost <= byteLimit else { return }
        entries[url] = Entry(image: image, version: version, cost: cost)
        totalCost += cost
        trim()
    }

    public func remove(_ url: URL) {
        if let old = entries.removeValue(forKey: url) { totalCost -= old.cost }
    }
    public func removeAll() { entries.removeAll(); priority.removeAll(); totalCost = 0 }

    private func trim() {
        let allowed = Set(priority)
        for url in Array(entries.keys) where !allowed.contains(url) { remove(url) }
        for url in priority.reversed() where totalCost > byteLimit { remove(url) }
    }
}
