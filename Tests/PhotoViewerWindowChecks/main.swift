import AppKit
import ImageIO
import PhotoViewerCore
import Darwin

// Exercise the real window controller without showing windows or synthesizing input.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("FAIL: \(message)") }
}
func waitFor(_ message: String, whileWaiting: () -> Void = {}, until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline {
        whileWaiting()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    check(condition(), message)
}
func writeImage(_ url: URL, width: Int, height: Int) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    check(CGImageDestinationFinalize(destination), "Write image fixture")
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let first = folder.appendingPathComponent("1.png")
let second = folder.appendingPathComponent("2.png")
let replacement = folder.appendingPathComponent("replacement.dat")
try writeImage(first, width: 400, height: 200)
try writeImage(second, width: 800, height: 400)
let viewer = ViewerWindowController()
viewer.open(first, showWindow: false)
check(viewer.canvas.isLoading, "Initial load uses a loading state, not the welcome screen")
viewer.open(first, showWindow: false) // Duplicate while the decoder is still running.
waitFor("First image appears") { viewer.canvas.image != nil && !viewer.canvas.isLoading }
let originalFrame = viewer.canvas.image
viewer.canvas.zoom(1.5)
let originalScale = viewer.canvas.viewport.scale
var marker: UInt64 = 123
let status = withUnsafeBytes(of: &marker) { bytes in
    setxattr(first.path, "com.example.photoviewer.test", bytes.baseAddress, bytes.count, 0, 0)
}
check(status == 0, "Update fixture metadata")
RunLoop.main.run(until: Date().addingTimeInterval(0.8))
check(viewer.canvas.image === originalFrame, "Metadata event does not decode/display the image again")
check(viewer.canvas.viewport.scale == originalScale, "Metadata event preserves zoom")
viewer.open(first, showWindow: false)
check(viewer.canvas.image === originalFrame && !viewer.canvas.isLoading, "Duplicate open is immediately ignored")
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
check(viewer.canvas.image === originalFrame, "Duplicate open does not schedule a later reload")
check(viewer.canvas.viewport.scale == originalScale, "Duplicate open preserves zoom")
print("Checked metadata-only events and duplicate opens do not redisplay images")

viewer.navigate(1)
check(viewer.canvas.image !== originalFrame && !viewer.canvas.isLoading, "Prefetched next image displays synchronously")
check(viewer.canvas.viewport.imageSize.width == 800, "Next image is correct")
let nextFrame = viewer.canvas.image
// Force a cold open (opening a folder/file clears the cache).
viewer.open(first, showWindow: false)
check(viewer.canvas.image === nextFrame && viewer.canvas.isLoading, "Cold load keeps the previous image visible")
var blankFrames = 0
waitFor("Cold open completes", whileWaiting: { if viewer.canvas.image == nil { blankFrames += 1 } }) {
    !viewer.canvas.isLoading && viewer.canvas.viewport.imageSize.width == 400
}
check(blankFrames == 0, "No empty state during cold navigation")
print("Checked warm navigation and no blank frame during cold loads")

let oldFrame = viewer.canvas.image
try writeImage(replacement, width: 600, height: 300)
try Data(contentsOf: replacement).write(to: first, options: .atomic)
blankFrames = 0
waitFor("Atomic image replacement is reloaded", whileWaiting: { if viewer.canvas.image == nil { blankFrames += 1 } }) {
    viewer.canvas.viewport.imageSize.width == 600 && !viewer.canvas.isLoading
}
check(blankFrames == 0 && viewer.canvas.image !== oldFrame, "Real file replacement swaps frames without clearing the canvas")
let replacedFrame = viewer.canvas.image
RunLoop.main.run(until: Date().addingTimeInterval(0.8))
check(viewer.canvas.image === replacedFrame, "Replacement does not enter a reload loop")
try writeImage(first, width: 700, height: 350)
blankFrames = 0
waitFor("In-place image edit is reloaded", whileWaiting: { if viewer.canvas.image == nil { blankFrames += 1 } }) {
    viewer.canvas.viewport.imageSize.width == 700 && !viewer.canvas.isLoading
}
check(blankFrames == 0, "In-place edit does not clear the canvas")
print("Checked atomic replacements and in-place edits still reload without flashing")

try Data("corrupt".utf8).write(to: first, options: .atomic)
waitFor("Corrupt replacement reports an error") {
    viewer.canvas.image == nil && !viewer.canvas.isLoading && viewer.canvas.message == "Couldn’t display this image"
}
viewer.close()
print("Checked failed replacements report a real error")
print("\(failures) window-check failures")
exit(failures == 0 ? 0 : 1)
