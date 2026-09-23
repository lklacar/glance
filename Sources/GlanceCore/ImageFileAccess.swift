import Foundation

/// Filesystem operations are injected so slow/disconnected volumes can be tested.
/// Call these only from worker queues, never from the UI thread.
public struct ImageFileAccess {
    public struct Location {
        public let url: URL
        public let isDirectory: Bool
        public init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
    }
    public var resolve: (URL) throws -> Location = { input in
        let url = input.standardizedFileURL.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return Location(url: url, isDirectory: values.isDirectory == true)
    }
    public var scan: (URL) throws -> [URL] = FolderCatalog.scan
    public var version: (URL) -> ImageFileVersion? = { ImageFileVersion(url: $0) }
    public var load: (URL) throws -> DecodedImage = ImageDecoder.load
    public var exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    public var monitor: (URL, @escaping () -> Void) -> FileMonitor? = { FileMonitor(url: $0, handler: $1) }
    public init() {}
}
