import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    public static let identifiers = CGImageSourceCopyTypeIdentifiers() as! [String]
    public static let extensions: Set<String> = {
        var result = Set(identifiers.flatMap { UTType($0)?.tags[.filenameExtension] ?? [] })
        result.formUnion(["svg", "pdf", "jpg", "jpeg", "png", "apng", "gif", "webp", "avif", "heic", "heif", "tif", "tiff", "bmp", "ico", "icns", "psd", "jp2", "jxl", "dng", "cr2", "cr3", "nef", "arw", "orf", "raf", "rw2", "pef", "srw"])
        return result
    }()

    public static func accepts(_ url: URL) -> Bool {
        if extensions.contains(url.pathExtension.lowercased()) { return true }
        return (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
    }
}

public struct FolderCatalog {
    public private(set) var urls: [URL]
    public private(set) var index: Int
    public var current: URL? { urls.indices.contains(index) ? urls[index] : nil }

    public init(urls: [URL] = [], selecting: URL? = nil) {
        self.urls = urls
        index = selecting.flatMap { urls.firstIndex(of: $0) } ?? 0
    }

    public static func scan(_ folder: URL) throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey], options: [.skipsHiddenFiles])
            .filter { ImageFormats.accepts($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        return Array(Set(files))
            .sorted {
                let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            }
    }

    @discardableResult public mutating func move(_ delta: Int) -> URL? {
        guard !urls.isEmpty else { return nil }
        index = ((index + delta % urls.count) % urls.count + urls.count) % urls.count
        return current
    }

    public mutating func select(_ index: Int) {
        guard urls.indices.contains(index) else { return }
        self.index = index
    }

    /// Nearest neighbors first, wrapping just like arrow-key navigation.
    public func nearbyURLs(radius: Int = 3) -> [URL] {
        guard let current else { return [] }
        var result = [current]
        var seen: Set<URL> = [current]
        let steps = min(max(0, radius), urls.count - 1)
        guard steps > 0 else { return result }
        for distance in 1...steps {
            for candidate in [(index + distance) % urls.count, (index - distance + urls.count) % urls.count] {
                if seen.insert(urls[candidate]).inserted { result.append(urls[candidate]) }
            }
        }
        return result
    }

    public mutating func refresh(_ updated: [URL]) {
        let previous = current
        let oldIndex = index
        urls = updated
        index = previous.flatMap { updated.firstIndex(of: $0) } ?? min(oldIndex, max(0, updated.count - 1))
    }
}
