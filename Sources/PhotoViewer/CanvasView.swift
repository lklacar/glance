import AppKit
import PhotoViewerCore

final class CanvasView: NSView {
    var viewport = Viewport()
    var image: CGImage?
    private(set) var isLoading = false
    var quarterTurns = 0
    var message = "Drop an image here"
    var detail = "Or press ⌘O to open an image or folder"
    var onNavigate: ((Int) -> Void)?
    var onOpen: (() -> Void)?
    var onDrop: ((URL) -> Void)?
    var onZoom: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onEscape: (() -> Void)?
    private var dragPoint: CGPoint?
    private var isDropTarget = false
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Image viewer")
        setAccessibilityHelp("Left and right arrows change images. Scroll to zoom. Drag to pan. Press zero to fit.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func display(_ decoded: DecodedImage) {
        isLoading = false
        image = decoded.image; quarterTurns = 0
        viewport.nativeScale = 1 / (window?.backingScaleFactor ?? 1)
        viewport.imageSize = decoded.pixelSize; viewport.resize(bounds.size); viewport.fit()
        message = ""; detail = ""; needsDisplay = true; window?.invalidateCursorRects(for: self); onZoom?()
    }
    func beginLoading() {
        // Keep the last frame until the replacement is ready; never draw the
        // welcome/empty-state illustration between two image presentations.
        isLoading = true; message = ""; detail = ""; needsDisplay = true
        if image == nil { setAccessibilityValue("Loading image") }
    }
    func showMessage(_ title: String, detail: String) {
        isLoading = false
        image = nil; message = title; self.detail = detail; needsDisplay = true
        setAccessibilityValue(title + ". " + detail)
    }
    func fit() { viewport.fit(); needsDisplay = true; onZoom?() }
    func zoom(_ factor: CGFloat, at point: CGPoint? = nil) {
        guard image != nil else { return }
        viewport.zoom(to: viewport.scale * factor, anchor: point ?? CGPoint(x: bounds.midX, y: bounds.midY))
        needsDisplay = true; onZoom?()
    }
    func actualSize() {
        guard image != nil else { return }
        // One image pixel per screen pixel, including Retina displays.
        viewport.zoom(to: 1 / (window?.backingScaleFactor ?? 1), anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        needsDisplay = true; onZoom?()
    }
    func rotate() {
        guard image != nil else { return }
        quarterTurns = (quarterTurns + 1) % 4
        viewport.imageSize = CGSize(width: viewport.imageSize.height, height: viewport.imageSize.width)
        fit()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); viewport.resize(newSize); needsDisplay = true; onZoom?()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill(); bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            if !isLoading { drawWelcome() }; return
        }
        let rect = viewport.rect
        context.saveGState()
        context.clip(to: bounds)
        context.clip(to: rect)
        // A subtle checkerboard makes transparent pixels visible.
        context.setFillColor(NSColor(calibratedWhite: 0.18, alpha: 1).cgColor); context.fill(rect)
        context.setFillColor(NSColor(calibratedWhite: 0.22, alpha: 1).cgColor)
        let visible = rect.intersection(bounds)
        if !visible.isNull {
            let tile: CGFloat = 12
            for y in Int(floor(visible.minY / tile))...Int(ceil(visible.maxY / tile)) {
                for x in Int(floor(visible.minX / tile))...Int(ceil(visible.maxX / tile)) where (x + y) % 2 == 0 {
                    context.fill(CGRect(x: CGFloat(x) * tile, y: CGFloat(y) * tile, width: tile, height: tile))
                }
            }
        }
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        let rotated = quarterTurns % 2 == 1
        let size = rotated ? CGSize(width: rect.height, height: rect.width) : rect.size
        context.interpolationQuality = viewport.scale * (window?.backingScaleFactor ?? 1) >= 4 ? .none : .high
        context.draw(image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
        if isDropTarget { drawDropBorder() }
    }
    private func drawWelcome() {
        let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .ultraLight))?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
        symbol?.draw(in: CGRect(x: bounds.midX - 32, y: bounds.midY + 38, width: 64, height: 56))
        drawText(message, y: bounds.midY - 5, font: .systemFont(ofSize: 23, weight: .medium), color: .white)
        drawText(detail, y: bounds.midY - 48, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        if isDropTarget { drawDropBorder() }
    }
    private func drawText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: CGRect(x: 40, y: y - 30, width: max(0, bounds.width - 80), height: 65),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func drawDropBorder() {
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 12), xRadius: 14, yRadius: 14)
        path.lineWidth = 3; path.stroke()
    }
    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
            viewport.pan(x: event.scrollingDeltaX, y: -event.scrollingDeltaY); needsDisplay = true
        } else {
            guard event.momentumPhase == [] else { return }
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.012 : 0.12)
            zoom(exp(min(0.5, max(-0.5, delta))), at: convert(event.locationInWindow, from: nil))
        }
    }
    override func magnify(with event: NSEvent) { zoom(max(0.1, 1 + event.magnification), at: convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if image == nil { if !isLoading { onOpen?() }; return }
        if event.clickCount == 2 { viewport.fitsWindow ? actualSize() : fit(); return }
        dragPoint = convert(event.locationInWindow, from: nil); NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let previous = dragPoint { viewport.pan(x: point.x - previous.x, y: point.y - previous.y); needsDisplay = true }
        dragPoint = point
    }
    override func mouseUp(with event: NSEvent) { if dragPoint != nil { NSCursor.pop() }; dragPoint = nil }
    override func resetCursorRects() { if image != nil { addCursorRect(bounds, cursor: .openHand) } }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onNavigate?(-1)
        case 124: onNavigate?(1)
        case 53: onEscape?()
        case 49: onTogglePlayback?()
        case 115: onNavigate?(Int.min)
        case 119: onNavigate?(Int.max)
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoom(1.25)
            case "-": zoom(0.8)
            case "0": fit()
            case "1": actualSize()
            default: super.keyDown(with: event)
            }
        }
    }
    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = droppedURL(sender) != nil; needsDisplay = true; return isDropTarget ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { isDropTarget = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false; needsDisplay = true
        guard let url = droppedURL(sender) else { return false }; onDrop?(url); return true
    }
}
