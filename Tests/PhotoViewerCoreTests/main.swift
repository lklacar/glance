import AppKit
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
print("\(failures) failures")
exit(failures == 0 ? 0 : 1)
