import AppKit
import Darwin
import ImageIO
import PhotoViewerCore


private var failures = 0
private func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL: \(message) at \(file):\(line)")
}
private func expectTrue(_ condition: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !condition { fail(message, file: file, line: line) }
}
private func expectFalse(_ condition: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { expectTrue(!condition, message, file: file, line: line) }
private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    expectTrue(actual == expected, "\(message) expected \(expected), got \(actual)", file: file, line: line)
}
private func expectEqual<T: BinaryFloatingPoint>(_ actual: T, _ expected: T, accuracy: T, file: StaticString = #filePath, line: UInt = #line) {
    expectTrue(abs(actual - expected) <= accuracy, "expected \(expected), got \(actual)", file: file, line: line)
}
private func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value == nil, "expected nil", file: file, line: line) }
private func expectNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value != nil, "expected non-nil", file: file, line: line) }
private struct CheckError: Error {}
private func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw CheckError() }; return value }
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("expected error", file: file, line: line) } catch {}
}

final class PhotoViewerCoreTests {
    private var temporary: URL!
    func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    private func file(_ name: String) -> URL { temporary.appendingPathComponent(name) }
    private func image(width: Int = 80, height: Int = 40) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
    private func write(_ name: String, type: String = "public.png", properties: [CFString: Any] = [:]) throws -> URL {
        let url = file(name)
        let destination = try unwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, type == "com.microsoft.ico" ? image(width: 32, height: 32) : image(), properties as CFDictionary)
        expectTrue(CGImageDestinationFinalize(destination))
        return url
    }
    func testNaturalOrderFilteringAndNavigationWraps() throws {
        for name in ["photo10.png", "photo2.JPG", "photo1.png", ".hidden.png", "notes.txt"] {
            try Data().write(to: file(name))
        }
        try FileManager.default.createDirectory(at: file("folder.png"), withIntermediateDirectories: true)
        let urls = try FolderCatalog.scan(temporary)
        expectEqual(urls.map(\.lastPathComponent), ["photo1.png", "photo2.JPG", "photo10.png"])
        var catalog = FolderCatalog(urls: urls)
        expectEqual(catalog.move(-1), urls[2]); expectEqual(catalog.move(1), urls[0])
        expectEqual(catalog.move(7), urls[1]); expectEqual(catalog.move(-7), urls[0])
        expectNotNil(catalog.move(Int.max)); expectNotNil(catalog.move(Int.min))
    }
    func testEmptyAndSingleImageFolders() {
        var empty = FolderCatalog(); expectNil(empty.move(1)); empty.refresh([]); expectNil(empty.current)
        var single = FolderCatalog(urls: [file("one.png")])
        expectEqual(single.move(1), file("one.png")); expectEqual(single.move(-1), file("one.png"))
    }
    func testRefreshPreservesSelectionAndHandlesRemoval() {
        let a = file("a.png"), b = file("b.png"), c = file("c.png")
        var catalog = FolderCatalog(urls: [a, b, c], selecting: b)
        catalog.refresh([c, a, b]); expectEqual(catalog.current, b)
        catalog.refresh([c, a]); expectEqual(catalog.current, a)
        catalog.refresh([]); expectNil(catalog.current)
    }
    func testViewportAnchoredZoomAndPanClamping() {
        var viewport = Viewport(); viewport.imageSize = CGSize(width: 1000, height: 1000)
        viewport.resize(CGSize(width: 500, height: 500)); viewport.fit()
        expectEqual(viewport.scale, 0.5)
        let anchor = CGPoint(x: 125, y: 125)
        let before = (anchor.x - viewport.rect.minX) / viewport.scale
        viewport.zoom(to: 1, anchor: anchor)
        expectEqual((anchor.x - viewport.rect.minX) / viewport.scale, before, accuracy: 0.001)
        viewport.pan(x: 10000, y: -10000)
        expectEqual(viewport.rect.minX, 0); expectEqual(viewport.rect.maxY, 500)
        viewport.zoom(to: .infinity, anchor: .zero); expectTrue(viewport.scale.isFinite)
        viewport.fit(); viewport.resize(CGSize(width: 200, height: 300)); expectEqual(viewport.scale, 0.2)
    }
    func testSmallImagesAreNotEnlargedByFit() {
        var viewport = Viewport(); viewport.imageSize = CGSize(width: 20, height: 10)
        viewport.resize(CGSize(width: 1000, height: 1000)); viewport.fit(); expectEqual(viewport.scale, 1)
    }
    func testNativeFormatRoundTrips() throws {
        let writable = CGImageDestinationCopyTypeIdentifiers() as! [String]
        let cases = [("png", "public.png"), ("jpg", "public.jpeg"), ("tiff", "public.tiff"),
                     ("gif", "com.compuserve.gif"), ("bmp", "com.microsoft.bmp"), ("jp2", "public.jpeg-2000"),
                     ("heic", "public.heic"), ("ico", "com.microsoft.ico")]
        for (ext, type) in cases where writable.contains(type) {
            let url = try write("test.\(ext)", type: type)
            let decoded = try ImageDecoder.load(url)
            expectEqual(decoded.pixelSize, ext == "ico" ? CGSize(width: 32, height: 32) : CGSize(width: 80, height: 40), ext)
            expectEqual(decoded.image.width, ext == "ico" ? 32 : 80, ext)
            expectFalse(decoded.isDownsampled, ext)
        }
    }
    func testEXIFOrientationAppliedExactlyOnce() throws {
        let url = try write("rotated.jpg", type: "public.jpeg", properties: [kCGImagePropertyOrientation: 6])
        let decoded = try ImageDecoder.load(url)
        expectEqual(decoded.pixelSize, CGSize(width: 40, height: 80))
        expectEqual(decoded.image.width, 40); expectEqual(decoded.image.height, 80)
    }
    func testAnimationFramesAndTiming() throws {
        let url = file("animated.gif")
        let destination = try unwrap(CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        for _ in 0..<2 {
            CGImageDestinationAddImage(destination, image(), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        expectTrue(CGImageDestinationFinalize(destination))
        let decoded = try ImageDecoder.load(url)
        expectEqual(decoded.frameCount, 2); expectNotNil(decoded.frame(at: 1))
        expectEqual(decoded.duration(at: 0), 0.2, accuracy: 0.01)
    }
    func testCorruptAndMissingImagesFailCleanly() throws {
        try Data("not an image".utf8).write(to: file("broken.png"))
        expectThrows(try ImageDecoder.load(file("broken.png")))
        expectThrows(try ImageDecoder.load(file("missing.jpg")))
        expectThrows(try ImageDecoder.load(URL(string: "https://example.com/photo.jpg")!))
    }
    func testSVGAndPDFFallback() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"40\"><rect width=\"80\" height=\"40\" fill=\"red\"/></svg>"
        try Data(svg.utf8).write(to: file("vector.svg"))
        expectEqual(try ImageDecoder.load(file("vector.svg")).pixelSize, CGSize(width: 80, height: 40))
        var bounds = CGRect(x: 0, y: 0, width: 80, height: 40)
        let context = try unwrap(CGContext(file("document.pdf") as CFURL, mediaBox: &bounds, nil))
        context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(bounds)
        context.endPDFPage(); context.closePDF()
        expectEqual(try ImageDecoder.load(file("document.pdf")).pixelSize, CGSize(width: 80, height: 40))
    }
    func testLargeImageDecodingIsBounded() throws {
        let url = file("large.tiff")
        let destination = try unwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil))
        autoreleasepool {
            CGImageDestinationAddImage(destination, image(width: 9000, height: 6000), nil)
        }
        expectTrue(CGImageDestinationFinalize(destination))
        let decoded = try ImageDecoder.load(url)
        expectTrue(decoded.isDownsampled)
        expectEqual(decoded.pixelSize, CGSize(width: 9000, height: 6000))
        expectTrue(Double(decoded.image.width * decoded.image.height) <= ImageDecoder.pixelBudget + 20000)
    }
    func testRetinaFitAndManualZoomSurviveResize() {
        var viewport = Viewport(); viewport.nativeScale = 0.5
        viewport.imageSize = CGSize(width: 80, height: 40); viewport.resize(CGSize(width: 1000, height: 500))
        expectEqual(viewport.scale, 0.5)
        viewport.zoom(to: 2, anchor: CGPoint(x: 500, y: 250)); viewport.resize(CGSize(width: 1200, height: 600))
        expectEqual(viewport.scale, 2); expectFalse(viewport.fitsWindow)
    }
    func testIndependentFormatFixtures() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        for url in try FolderCatalog.scan(fixtures) {
            let decoded = try ImageDecoder.load(url)
            expectEqual(decoded.pixelSize, CGSize(width: 80, height: 40), url.lastPathComponent)
            if url.lastPathComponent.hasPrefix("animated") {
                expectEqual(decoded.frameCount, 2, url.lastPathComponent)
                expectNotNil(decoded.frame(at: 1))
                expectEqual(decoded.duration(at: 0), 0.2, accuracy: 0.01)
                expectEqual(decoded.duration(at: 1), 0.3, accuracy: 0.01)
            } else { expectEqual(decoded.frameCount, 1, url.lastPathComponent) }
            print("  Decoded \(url.lastPathComponent)")
        }
    }
    func testNeighborWindowWrapsWithoutDuplicates() {
        let urls = (0..<10).map { file("image\($0).png") }
        let catalog = FolderCatalog(urls: urls)
        expectEqual(catalog.nearbyURLs(), [urls[0], urls[1], urls[9], urls[2], urls[8], urls[3], urls[7]])
        expectEqual(FolderCatalog().nearbyURLs(), [])
        expectEqual(FolderCatalog(urls: [urls[0]]).nearbyURLs(), [urls[0]])
        expectEqual(FolderCatalog(urls: Array(urls.prefix(2))).nearbyURLs(), Array(urls.prefix(2)))
        expectEqual(FolderCatalog(urls: Array(urls.prefix(3))).nearbyURLs(), Array(urls.prefix(3)))
        expectEqual(catalog.nearbyURLs(radius: -1), [urls[0]])
    }
    func testCacheBudgetPrefersNearestImages() throws {
        let urls = try (0..<4).map { try write("image\($0).png") }
        let images = try urls.map { try ImageDecoder.load($0) }
        let cost = images[0].image.bytesPerRow * images[0].image.height + images[0].fileSize
        let cache = ImageCache(byteLimit: cost * 2)
        cache.setPriority(urls)
        for index in [3, 2, 1, 0] {
            cache.insert(images[index], for: urls[index], version: try unwrap(ImageFileVersion(url: urls[index])))
            expectTrue(cache.totalCost <= cache.byteLimit)
        }
        expectTrue(cache.image(for: urls[0]) === images[0])
        expectTrue(cache.image(for: urls[1]) === images[1])
        expectNil(cache.image(for: urls[2])); expectNil(cache.image(for: urls[3]))
        expectEqual(cache.count, 2)
        cache.setPriority([urls[3]])
        expectEqual(cache.count, 0); expectEqual(cache.totalCost, 0)
        let tiny = ImageCache(byteLimit: 1); tiny.setPriority(urls)
        tiny.insert(images[0], for: urls[0], version: try unwrap(ImageFileVersion(url: urls[0])))
        expectEqual(tiny.count, 0)
    }
    func testCacheRejectsEditedReplacedAndRemovedFiles() throws {
        let url = try write("image.png"), decoded = try ImageDecoder.load(url)
        let cache = ImageCache(); cache.setPriority([url])
        let version = try unwrap(ImageFileVersion(url: url))
        cache.insert(decoded, for: url, version: version)
        expectTrue(cache.image(for: url) === decoded)
        let original = try Data(contentsOf: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        // Replace with the same bytes and mtime. The inode/ctime still changes.
        try original.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        expectNil(cache.image(for: url))
        cache.insert(decoded, for: url, version: version)
        expectNil(cache.image(for: url), file: #filePath, line: #line)
        cache.insert(decoded, for: url, version: try unwrap(ImageFileVersion(url: url)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        expectNil(cache.image(for: url))
        cache.insert(decoded, for: url, version: try unwrap(ImageFileVersion(url: url)))
        try FileManager.default.removeItem(at: url)
        expectNil(cache.image(for: url)); expectEqual(cache.totalCost, 0)
    }
    func testWarmNavigationReusesDecodedImages() throws {
        let urls = try (0..<8).map { try write("image\($0).png") }
        var catalog = FolderCatalog(urls: urls)
        let cache = ImageCache(); cache.setPriority(catalog.nearbyURLs())
        var loaded: [URL: DecodedImage] = [:]
        for url in catalog.nearbyURLs() {
            let image = try ImageDecoder.load(url); loaded[url] = image
            cache.insert(image, for: url, version: try unwrap(ImageFileVersion(url: url)))
        }
        for delta in [1, 1, -1, -1, -1, -1, 1, 1] {
            let url = try unwrap(catalog.move(delta))
            expectTrue(cache.image(for: url) === loaded[url], "Warm navigation must reuse the decoded object")
        }
        cache.removeAll(); expectEqual(cache.totalCost, 0); expectEqual(cache.count, 0)
        // Simulate a completion from a canceled folder after switching folders.
        cache.setPriority([file("another-folder.png")])
        cache.insert(try unwrap(loaded[urls[0]]), for: urls[0], version: try unwrap(ImageFileVersion(url: urls[0])))
        expectNil(cache.image(for: urls[0]))
    }
    func testMetadataChangesKeepCachedImage() throws {
        let url = try write("metadata.png")
        let image = try ImageDecoder.load(url)
        let version = try unwrap(ImageFileVersion(url: url))
        let cache = ImageCache(); cache.setPriority([url]); cache.insert(image, for: url, version: version)
        var marker: UInt64 = 123
        let status = withUnsafeBytes(of: &marker) { bytes in
            setxattr(url.path, "com.example.photoviewer.test", bytes.baseAddress, bytes.count, 0, 0)
        }
        expectEqual(status, 0)
        expectEqual(ImageFileVersion(url: url), version)
        expectTrue(cache.image(for: url) === image)
    }
    func testFileMonitorIgnoresMetadataButDetectsContentWrites() throws {
        let url = try write("watched.png")
        var events = 0
        let monitor = try unwrap(FileMonitor(url: url) { events += 1 })
        var marker: UInt64 = 123
        let status = withUnsafeBytes(of: &marker) { bytes in
            setxattr(url.path, "com.example.photoviewer.test", bytes.baseAddress, bytes.count, 0, 0)
        }
        expectEqual(status, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expectEqual(events, 0, "Metadata changes must not request an image reload")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        let deadline = Date().addingTimeInterval(2)
        while events == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expectTrue(events > 0, "Actual data writes must still trigger a reload")
        withExtendedLifetime(monitor) {}
    }
    func testCacheLookupTiming() throws {
        let url = file("timing.png")
        let destination = try unwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image(width: 2400, height: 1600), nil)
        expectTrue(CGImageDestinationFinalize(destination))
        let start = Date()
        let decoded = try ImageDecoder.load(url)
        let cold = Date().timeIntervalSince(start)
        let cache = ImageCache(); cache.setPriority([url])
        cache.insert(decoded, for: url, version: try unwrap(ImageFileVersion(url: url)))
        let warmStart = Date()
        for _ in 0..<1000 { expectTrue(cache.image(for: url) === decoded) }
        let warm = Date().timeIntervalSince(warmStart) / 1000
        print(String(format: "  2400×1600 PNG: cold decode %.2f ms; warm cache lookup %.3f ms average", cold * 1000, warm * 1000))
    }
    func testSmoothZoomConvergesAndKeepsPointerAnchored() {
        var viewport = Viewport(); viewport.imageSize = CGSize(width: 4000, height: 4000)
        viewport.resize(CGSize(width: 1000, height: 1000)); viewport.fit()
        let anchor = CGPoint(x: 300, y: 400)
        let imagePoint = CGPoint(x: (anchor.x - viewport.rect.minX) / viewport.scale,
                                 y: (anchor.y - viewport.rect.minY) / viewport.scale)
        var motion = SmoothZoom()
        motion.retarget(factor: 2, anchor: anchor, viewport: viewport)
        let target = motion.targetScale!
        for _ in 0..<60 {
            let before = viewport.scale
            motion.advance(seconds: 1.0 / 120, viewport: &viewport)
            expectTrue(viewport.scale >= before && viewport.scale <= target)
            expectEqual((anchor.x - viewport.rect.minX) / viewport.scale, imagePoint.x, accuracy: 0.00001)
            expectEqual((anchor.y - viewport.rect.minY) / viewport.scale, imagePoint.y, accuracy: 0.00001)
        }
        expectEqual(viewport.scale, target); expectNil(motion.targetScale)
    }
    func testSmoothZoomRefreshRatesReversalAndCancellation() {
        var sixty = Viewport(); sixty.imageSize = CGSize(width: 4000, height: 4000)
        sixty.resize(CGSize(width: 1000, height: 1000)); sixty.fit()
        var oneTwenty = sixty, a = SmoothZoom(), b = SmoothZoom()
        let anchor = CGPoint(x: 500, y: 500)
        a.retarget(factor: 4, anchor: anchor, viewport: sixty)
        b.retarget(factor: 4, anchor: anchor, viewport: oneTwenty)
        for _ in 0..<5 { a.advance(seconds: 1.0 / 60, viewport: &sixty) }
        for _ in 0..<10 { b.advance(seconds: 1.0 / 120, viewport: &oneTwenty) }
        expectEqual(sixty.scale, oneTwenty.scale, accuracy: 0.000001)
        let beforeReverse = sixty.scale
        a.retarget(factor: 0.8, anchor: anchor, viewport: sixty)
        a.advance(seconds: 1.0 / 60, viewport: &sixty)
        expectTrue(sixty.scale < beforeReverse)
        a.cancel(); let stopped = sixty.scale
        expectFalse(a.advance(seconds: 1, viewport: &sixty)); expectEqual(sixty.scale, stopped)
        a.retarget(factor: .nan, anchor: anchor, viewport: sixty); expectNil(a.targetScale)
    }
    func testZoomInputIsBoundedAndPrecise() {
        expectEqual(SmoothZoom.scrollFactor(delta: 0, precise: false), 1)
        expectEqual(SmoothZoom.scrollFactor(delta: .infinity, precise: true), 1)
        expectTrue(SmoothZoom.scrollFactor(delta: 1, precise: true) < SmoothZoom.scrollFactor(delta: 1, precise: false))
        expectTrue(SmoothZoom.scrollFactor(delta: 10000, precise: false) < 1.25)
        expectEqual(SmoothZoom.scrollFactor(delta: 5, precise: true) * SmoothZoom.scrollFactor(delta: -5, precise: true), 1, accuracy: 0.000001)
    }
    func testMajorFormatsAreDiscovered() {
        for ext in ["JPG", "png", "heic", "webp", "avif", "jxl", "gif", "tiff", "bmp", "svg", "pdf", "psd", "dng", "cr3", "nef"] {
            expectTrue(ImageFormats.accepts(file("image.\(ext)")), ext)
        }
        expectFalse(ImageFormats.accepts(file("notes.txt")))
    }
}

let suite = PhotoViewerCoreTests()
do { try suite.setUpWithError(); try suite.testNaturalOrderFilteringAndNavigationWraps(); try suite.tearDownWithError(); print("Checked testNaturalOrderFilteringAndNavigationWraps") } catch { fail("testNaturalOrderFilteringAndNavigationWraps: \(error)") }
do { try suite.setUpWithError(); suite.testEmptyAndSingleImageFolders(); try suite.tearDownWithError(); print("Checked testEmptyAndSingleImageFolders") } catch { fail("testEmptyAndSingleImageFolders: \(error)") }
do { try suite.setUpWithError(); suite.testRefreshPreservesSelectionAndHandlesRemoval(); try suite.tearDownWithError(); print("Checked testRefreshPreservesSelectionAndHandlesRemoval") } catch { fail("testRefreshPreservesSelectionAndHandlesRemoval: \(error)") }
do { try suite.setUpWithError(); suite.testViewportAnchoredZoomAndPanClamping(); try suite.tearDownWithError(); print("Checked testViewportAnchoredZoomAndPanClamping") } catch { fail("testViewportAnchoredZoomAndPanClamping: \(error)") }
do { try suite.setUpWithError(); suite.testSmallImagesAreNotEnlargedByFit(); try suite.tearDownWithError(); print("Checked testSmallImagesAreNotEnlargedByFit") } catch { fail("testSmallImagesAreNotEnlargedByFit: \(error)") }
do { try suite.setUpWithError(); try suite.testNativeFormatRoundTrips(); try suite.tearDownWithError(); print("Checked testNativeFormatRoundTrips") } catch { fail("testNativeFormatRoundTrips: \(error)") }
do { try suite.setUpWithError(); try suite.testEXIFOrientationAppliedExactlyOnce(); try suite.tearDownWithError(); print("Checked testEXIFOrientationAppliedExactlyOnce") } catch { fail("testEXIFOrientationAppliedExactlyOnce: \(error)") }
do { try suite.setUpWithError(); try suite.testAnimationFramesAndTiming(); try suite.tearDownWithError(); print("Checked testAnimationFramesAndTiming") } catch { fail("testAnimationFramesAndTiming: \(error)") }
do { try suite.setUpWithError(); try suite.testCorruptAndMissingImagesFailCleanly(); try suite.tearDownWithError(); print("Checked testCorruptAndMissingImagesFailCleanly") } catch { fail("testCorruptAndMissingImagesFailCleanly: \(error)") }
do { try suite.setUpWithError(); try suite.testSVGAndPDFFallback(); try suite.tearDownWithError(); print("Checked testSVGAndPDFFallback") } catch { fail("testSVGAndPDFFallback: \(error)") }
do { try suite.setUpWithError(); suite.testMajorFormatsAreDiscovered(); try suite.tearDownWithError(); print("Checked testMajorFormatsAreDiscovered") } catch { fail("testMajorFormatsAreDiscovered: \(error)") }
do { try suite.setUpWithError(); try suite.testIndependentFormatFixtures(); try suite.tearDownWithError(); print("Checked testIndependentFormatFixtures") } catch { fail("testIndependentFormatFixtures: \(error)") }
do { try suite.setUpWithError(); try suite.testLargeImageDecodingIsBounded(); try suite.tearDownWithError(); print("Checked testLargeImageDecodingIsBounded") } catch { fail("testLargeImageDecodingIsBounded: \(error)") }
suite.testRetinaFitAndManualZoomSurviveResize()
print("Checked testRetinaFitAndManualZoomSurviveResize")
do { try suite.setUpWithError(); suite.testNeighborWindowWrapsWithoutDuplicates(); try suite.tearDownWithError(); print("Checked testNeighborWindowWrapsWithoutDuplicates") } catch { fail("testNeighborWindowWrapsWithoutDuplicates: \(error)") }
do { try suite.setUpWithError(); try suite.testCacheBudgetPrefersNearestImages(); try suite.tearDownWithError(); print("Checked testCacheBudgetPrefersNearestImages") } catch { fail("testCacheBudgetPrefersNearestImages: \(error)") }
do { try suite.setUpWithError(); try suite.testCacheRejectsEditedReplacedAndRemovedFiles(); try suite.tearDownWithError(); print("Checked testCacheRejectsEditedReplacedAndRemovedFiles") } catch { fail("testCacheRejectsEditedReplacedAndRemovedFiles: \(error)") }
do { try suite.setUpWithError(); try suite.testWarmNavigationReusesDecodedImages(); try suite.tearDownWithError(); print("Checked testWarmNavigationReusesDecodedImages") } catch { fail("testWarmNavigationReusesDecodedImages: \(error)") }
do { try suite.setUpWithError(); try suite.testCacheLookupTiming(); try suite.tearDownWithError(); print("Checked testCacheLookupTiming") } catch { fail("testCacheLookupTiming: \(error)") }
do { try suite.setUpWithError(); try suite.testMetadataChangesKeepCachedImage(); try suite.tearDownWithError(); print("Checked testMetadataChangesKeepCachedImage") } catch { fail("testMetadataChangesKeepCachedImage: \(error)") }
do { try suite.setUpWithError(); try suite.testFileMonitorIgnoresMetadataButDetectsContentWrites(); try suite.tearDownWithError(); print("Checked testFileMonitorIgnoresMetadataButDetectsContentWrites") } catch { fail("testFileMonitorIgnoresMetadataButDetectsContentWrites: \(error)") }
suite.testSmoothZoomConvergesAndKeepsPointerAnchored()
print("Checked testSmoothZoomConvergesAndKeepsPointerAnchored")
suite.testSmoothZoomRefreshRatesReversalAndCancellation()
print("Checked testSmoothZoomRefreshRatesReversalAndCancellation")
suite.testZoomInputIsBoundedAndPrecise()
print("Checked testZoomInputIsBoundedAndPrecise")
print("\(failures) failures")
exit(failures == 0 ? 0 : 1)
