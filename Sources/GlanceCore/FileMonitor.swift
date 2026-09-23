import Foundation
import Darwin

/// Observe data changes and replacement, not Finder tags or last-opened metadata.
public final class FileMonitor {
    private var source: DispatchSourceFileSystemObject?
    public init?(url: URL, handler: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .revoke], queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { DispatchQueue.global(qos: .utility).async { close(descriptor) } }
        self.source = source; source.resume()
    }
    deinit { source?.cancel() }
}

