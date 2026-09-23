import AppKit
import QuartzCore
import PhotoViewerCore

private final class ZoomDisplayLinkTarget: NSObject {
    weak var canvas: CanvasView?
    init(_ canvas: CanvasView) { self.canvas = canvas }
    @objc func tick(_ link: CADisplayLink) { canvas?.advanceZoom(link) }
}

final class CanvasView: NSView {
    var viewport = Viewport() { didSet { updateImageLayers() } }
    var image: CGImage? {
        didSet {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            imageLayer.contents = image
            CATransaction.commit()
            updateImageLayers()
            if (oldValue == nil) != (image == nil) { needsDisplay = true }
            if image == nil { stopZoomAnimation() }
        }
    }
    let imageLayer = CALayer()
    private let transparencyLayer = CALayer()
    private let checkerLayer = CAShapeLayer()
    private let imageMask = CALayer()
    private let dropLayer = CAShapeLayer()
    private var zoomMotion = SmoothZoom()
    private var zoomDisplayLink: CADisplayLink?
    private lazy var zoomDisplayTarget = ZoomDisplayLinkTarget(self)
    private var lastZoomTime: CFTimeInterval = 0
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
    private var isDropTarget = false { didSet { updateDropBorder() } }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.name = "Image"
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .linear
        transparencyLayer.name = "Transparency"
        transparencyLayer.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        checkerLayer.fillColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        imageMask.backgroundColor = NSColor.black.cgColor
        transparencyLayer.addSublayer(checkerLayer)
        transparencyLayer.mask = imageMask
        layer?.addSublayer(transparencyLayer)
        layer?.addSublayer(imageLayer)
        dropLayer.fillColor = nil; dropLayer.lineWidth = 3
        layer?.addSublayer(dropLayer)
        rebuildCheckerboard()
        updateImageLayers()
        updateDropBorder()
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Image viewer")
        setAccessibilityHelp("Left and right arrows change images. Scroll to zoom. Drag to pan. Press zero to fit.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func display(_ decoded: DecodedImage) {
        stopZoomAnimation()
        isLoading = false
        image = decoded.image; quarterTurns = 0
        viewport.nativeScale = 1 / (window?.backingScaleFactor ?? 1)
        viewport.imageSize = decoded.pixelSize; viewport.resize(bounds.size); viewport.fit()
        message = ""; detail = ""; needsDisplay = true; window?.invalidateCursorRects(for: self); onZoom?()
    }
    func beginLoading() {
        stopZoomAnimation()
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
    func fit() { stopZoomAnimation(); viewport.fit(); onZoom?() }
    func zoom(_ factor: CGFloat, at point: CGPoint? = nil, animated: Bool = false) {
        guard image != nil, factor.isFinite, factor > 0 else { return }
        let anchor = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        if animated, window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            zoomMotion.retarget(factor: factor, anchor: anchor, viewport: viewport)
            if zoomDisplayLink == nil {
                lastZoomTime = CACurrentMediaTime()
                let link = displayLink(target: zoomDisplayTarget, selector: #selector(ZoomDisplayLinkTarget.tick(_:)))
                zoomDisplayLink = link
                link.add(to: .main, forMode: .common)
            }
        } else {
            stopZoomAnimation()
            viewport.zoom(to: viewport.scale * factor, anchor: anchor)
            onZoom?()
        }
    }
    fileprivate func advanceZoom(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = max(0.001, now - lastZoomTime)
        lastZoomTime = now
        let continuing = zoomMotion.advance(seconds: elapsed, viewport: &viewport)
        onZoom?()
        if !continuing { stopZoomAnimation() }
    }
    func stopZoomAnimation() {
        zoomDisplayLink?.invalidate(); zoomDisplayLink = nil; zoomMotion.cancel()
    }
    deinit { zoomDisplayLink?.invalidate() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopZoomAnimation() }
    }
    func actualSize() {
        guard image != nil else { return }
        stopZoomAnimation()
        viewport.zoom(to: 1 / (window?.backingScaleFactor ?? 1), anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        onZoom?()
    }
    func rotate() {
        guard image != nil else { return }
        quarterTurns = (quarterTurns + 1) % 4
        viewport.imageSize = CGSize(width: viewport.imageSize.height, height: viewport.imageSize.width)
        fit()
    }
    override func setFrameSize(_ newSize: NSSize) {
        guard newSize != frame.size else { super.setFrameSize(newSize); return }
        stopZoomAnimation()
        super.setFrameSize(newSize); viewport.resize(newSize)
        rebuildCheckerboard(); updateDropBorder()
        if image == nil { needsDisplay = true }
        onZoom?()
    }
    private func updateImageLayers() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.isHidden = image == nil
        let alpha = image?.alphaInfo
        transparencyLayer.isHidden = image == nil || alpha == CGImageAlphaInfo.none || alpha == .noneSkipFirst || alpha == .noneSkipLast
        let rect = viewport.rect
        transparencyLayer.frame = bounds
        imageMask.frame = rect
        imageLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        let rotated = quarterTurns % 2 == 1
        imageLayer.bounds = CGRect(origin: .zero, size: rotated ? CGSize(width: rect.height, height: rect.width) : rect.size)
        imageLayer.setAffineTransform(CGAffineTransform(rotationAngle: -CGFloat(quarterTurns) * .pi / 2))
        CATransaction.commit()
    }
    private func rebuildCheckerboard() {
        // Build this once per resize. Zoom only changes the mask and image geometry.
        let path = CGMutablePath()
        let tile: CGFloat = 12
        if bounds.width > 0, bounds.height > 0 {
            for y in 0...Int(ceil(bounds.height / tile)) {
                for x in 0...Int(ceil(bounds.width / tile)) where (x + y) % 2 == 0 {
                    path.addRect(CGRect(x: CGFloat(x) * tile, y: CGFloat(y) * tile, width: tile, height: tile))
                }
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        checkerLayer.frame = bounds; checkerLayer.path = path
        CATransaction.commit()
    }
    private func updateDropBorder() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dropLayer.isHidden = !isDropTarget
        dropLayer.strokeColor = NSColor.controlAccentColor.cgColor
        dropLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 12, dy: 12), cornerWidth: 14, cornerHeight: 14, transform: nil)
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill(); bounds.fill()
        if image == nil && !isLoading { drawWelcome() }
    }
    private func drawWelcome() {
        let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .ultraLight))?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
        symbol?.draw(in: CGRect(x: bounds.midX - 32, y: bounds.midY + 38, width: 64, height: 56))
        drawText(message, y: bounds.midY - 5, font: .systemFont(ofSize: 23, weight: .medium), color: .white)
        drawText(detail, y: bounds.midY - 48, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
    }
    private func drawText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: CGRect(x: 40, y: y - 30, width: max(0, bounds.width - 80), height: 65),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
            stopZoomAnimation()
            viewport.pan(x: event.scrollingDeltaX, y: -event.scrollingDeltaY)
        } else {
            guard event.scrollingDeltaY != 0 else { return }
            let factor = SmoothZoom.scrollFactor(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            zoom(factor, at: convert(event.locationInWindow, from: nil), animated: !event.hasPreciseScrollingDeltas)
        }
    }
    override func magnify(with event: NSEvent) { zoom(max(0.1, 1 + event.magnification), at: convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        stopZoomAnimation()
        if image == nil { if !isLoading { onOpen?() }; return }
        if event.clickCount == 2 { viewport.fitsWindow ? actualSize() : fit(); return }
        dragPoint = convert(event.locationInWindow, from: nil); NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let previous = dragPoint { viewport.pan(x: point.x - previous.x, y: point.y - previous.y) }
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
            case "+", "=": zoom(1.25, animated: true)
            case "-": zoom(0.8, animated: true)
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
