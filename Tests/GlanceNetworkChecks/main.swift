import AppKit
import ImageIO
import GlanceCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("FAIL: \(message)") }
}
func pump(_ seconds: Double = 0.02) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
func waitFor(_ message: String, _ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(4)
    while !predicate() && Date() < deadline { pump(0.005) }
    check(predicate(), message)
}
final class Gate {
    private let condition = NSCondition()
    private var released = false
    private var visits = 0
    var entered: Bool { condition.lock(); defer { condition.unlock() }; return visits > 0 }
    func wait() {
        condition.lock(); defer { condition.unlock() }; visits += 1
        let deadline = Date().addingTimeInterval(8)
        while !released { if !condition.wait(until: deadline) { break } }
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
final class Audit {
    private let lock = NSLock()
    private var mainCalls: [String] = []
    private var counts: [URL: Int] = [:]
    func record(_ name: String) { lock.lock(); defer { lock.unlock() }; if Thread.isMainThread { mainCalls.append(name) } }
    func loaded(_ url: URL) { lock.lock(); defer { lock.unlock() }; counts[url, default: 0] += 1 }
    func loads(_ url: URL) -> Int { lock.lock(); defer { lock.unlock() }; return counts[url, default: 0] }
    var violations: [String] { lock.lock(); defer { lock.unlock() }; return mainCalls }
    func access() -> ImageFileAccess {
        let base = ImageFileAccess()
        var access = base
        access.resolve = { self.record("resolve"); return try base.resolve($0) }
        access.scan = { self.record("scan"); return try base.scan($0) }
        access.version = { self.record("version"); return base.version($0) }
        access.exists = { self.record("exists"); return base.exists($0) }
        access.load = { self.record("load"); self.loaded($0); return try base.load($0) }
        access.monitor = { self.record("monitor"); return base.monitor($0, $1) }
        return access
    }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
func fixture(_ name: String, width: Int) -> URL {
    let url = directory.appendingPathComponent(name)
    let context = CGContext(data: nil, width: width, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    check(CGImageDestinationFinalize(destination), "Write fixture")
    return url.standardizedFileURL.resolvingSymlinksInPath()
}
let first = fixture("1.png", width: 100), second = fixture("2.png", width: 200), third = fixture("3.png", width: 300)
let audit = Audit()
func expectResponsive(_ action: () -> Void) {
    let start = Date(); action()
    check(Date().timeIntervalSince(start) < 0.25, "UI action returns without waiting for filesystem work")
    var heartbeat = false
    DispatchQueue.main.async { heartbeat = true }
    waitFor("Main run loop remains responsive") { heartbeat }
}
// A stalled initial directory lookup must not hold up Cancel or the next open.
do {
    let gate = Gate(); var access = audit.access(); let resolve = access.resolve
    access.resolve = { url in if url == first { gate.wait() }; return try resolve(url) }
    let viewer = ViewerWindowController(fileAccess: access)
    expectResponsive { viewer.open(first, showWindow: false) }
    waitFor("Slow location lookup entered") { gate.entered }
    check(viewer.canvas.isLoading, "Loading state appears before location lookup finishes")
    expectResponsive { viewer.cancelLoading(nil) }
    check(!viewer.canvas.isLoading && viewer.canvas.image == nil, "Cancel stops loading immediately")
    expectResponsive { viewer.open(second, showWindow: false) }
    waitFor("New local open bypasses a stalled lookup") { !viewer.canvas.isLoading && viewer.canvas.viewport.imageSize.width == 200 }
    let frame = viewer.canvas.image
    gate.release(); pump(0.1)
    check(viewer.canvas.image === frame, "Late location lookup cannot overwrite the new image")
    viewer.close()
}
// Background stat calls during navigation must not block the canvas, even on a cache hit.
do {
    let gate = Gate(); var access = audit.access(); let version = access.version
    let previousDecodeCount = audit.loads(second)
    // Initial preloading is allowed, then navigation's version check is stalled.
    let lock = NSLock(); var block = false
    access.version = { url in
        lock.lock(); let shouldBlock = block && url == second; lock.unlock()
        if shouldBlock { gate.wait() }
        return version(url)
    }
    let viewer = ViewerWindowController(fileAccess: access)
    viewer.open(first, showWindow: false)
    waitFor("Initial image and folder appear") { !viewer.canvas.isLoading && viewer.catalog.urls.count == 3 }
    waitFor("Second image was prefetched") { audit.loads(second) > previousDecodeCount }
    pump(0.2)
    let decodeCount = audit.loads(second)
    lock.lock(); block = true; lock.unlock()
    expectResponsive { viewer.navigate(1) }
    waitFor("Cache validation stalls off main") { gate.entered }
    check(viewer.canvas.image != nil && viewer.canvas.isLoading, "Previous image stays visible during cache validation")
    gate.release()
    waitFor("Warm navigation finishes") { !viewer.canvas.isLoading && viewer.canvas.viewport.imageSize.width == 200 }
    check(audit.loads(second) == decodeCount, "Async cache validation reuses decoded pixels")
    viewer.close()
}
// Superseding a blocked image read gets a second foreground slot; stale completion is ignored.
do {
    let gate = Gate(); var access = audit.access(); let load = access.load
    access.load = { url in if url == second { gate.wait() }; return try load(url) }
    let viewer = ViewerWindowController(fileAccess: access)
    viewer.handleMemoryPressure(.critical) // Disable speculative reads for this scenario.
    viewer.open(first, showWindow: false)
    waitFor("Navigation fixture loads") { !viewer.canvas.isLoading && viewer.catalog.urls.count == 3 }
    expectResponsive { viewer.navigate(1) }
    waitFor("Slow image read entered") { gate.entered }
    expectResponsive { viewer.navigate(1) }
    waitFor("Latest navigation bypasses blocked read") { !viewer.canvas.isLoading && viewer.canvas.viewport.imageSize.width == 300 }
    let frame = viewer.canvas.image
    gate.release(); pump(0.1)
    check(viewer.canvas.image === frame, "Stale image read cannot replace the latest frame")
    viewer.close()
}
// Slow enumeration and watcher creation must be independent of foreground rendering/closing.
do {
    let scanGate = Gate(), monitorGate = Gate(); var access = audit.access()
    let scan = access.scan, monitor = access.monitor
    access.scan = { url in scanGate.wait(); return try scan(url) }
    access.monitor = { url, callback in monitorGate.wait(); return monitor(url, callback) }
    let viewer = ViewerWindowController(fileAccess: access)
    viewer.open(first, showWindow: false)
    waitFor("Foreground image displays while scan and watches are stalled") { !viewer.canvas.isLoading && viewer.canvas.image != nil }
    check(scanGate.entered && monitorGate.entered, "Slow scan and watcher paths exercised")
    expectResponsive { viewer.close() }
    scanGate.release(); monitorGate.release(); pump(0.2)
    check(viewer.canvas.image == nil, "Late scan/watch completions cannot resurrect a closed window")
}
// A disconnected-share error ends the spinner and leaves navigation available.
do {
    var access = audit.access(); let load = access.load
    access.load = { url in
        if url == second { throw NSError(domain: NSPOSIXErrorDomain, code: 57, userInfo: nil) }
        return try load(url)
    }
    let viewer = ViewerWindowController(fileAccess: access)
    viewer.open(first, showWindow: false)
    waitFor("Failure fixture loads") { !viewer.canvas.isLoading && viewer.catalog.urls.count == 3 }
    viewer.navigate(1)
    waitFor("Disconnected read shows an error") { !viewer.canvas.isLoading && viewer.canvas.image == nil }
    check(viewer.canvas.message == "Couldn’t display this image", "Error replaces loading state")
    viewer.navigate(1)
    waitFor("Navigation recovers after read error") { !viewer.canvas.isLoading && viewer.canvas.viewport.imageSize.width == 300 }
    viewer.close()
}
check(audit.violations.isEmpty, "No filesystem operation ran on the main thread: \(audit.violations)")
print("Checked stalled location lookup, cache validation, decoding, folder scan, and file watchers")
print("Checked cancellation, latest-request delivery, cached pixel reuse, close, and read-error recovery")
print("\(failures) network-loading check failures")
exit(failures == 0 ? 0 : 1)
