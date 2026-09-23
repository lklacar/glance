import Foundation

public struct Viewport {
    public var imageSize = CGSize.zero
    public var bounds = CGSize.zero
    public var nativeScale: CGFloat = 1
    public private(set) var scale: CGFloat = 1
    public private(set) var offset = CGPoint.zero
    public private(set) var fitsWindow = true
    public init() {}
    public var fitScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(0.00001, min(bounds.width / imageSize.width, bounds.height / imageSize.height, nativeScale))
    }
    public var rect: CGRect {
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + offset.x,
                      y: (bounds.height - size.height) / 2 + offset.y, width: size.width, height: size.height)
    }
    public mutating func fit() { fitsWindow = true; scale = fitScale; offset = .zero }
    public mutating func resize(_ size: CGSize) { bounds = size; if fitsWindow { fit() } else { clamp() } }
    public mutating func zoom(to requested: CGFloat, anchor: CGPoint) {
        guard requested.isFinite, scale > 0 else { return }
        let next = min(32, max(min(0.01, fitScale), requested))
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let ratio = next / scale
        offset = CGPoint(x: (offset.x + center.x - anchor.x) * ratio + anchor.x - center.x,
                         y: (offset.y + center.y - anchor.y) * ratio + anchor.y - center.y)
        scale = next; fitsWindow = false; clamp()
    }
    public mutating func pan(x: CGFloat, y: CGFloat) { offset.x += x; offset.y += y; clamp() }
    private mutating func clamp() {
        let x = max(0, (imageSize.width * scale - bounds.width) / 2)
        let y = max(0, (imageSize.height * scale - bounds.height) / 2)
        offset.x = min(x, max(-x, offset.x)); offset.y = min(y, max(-y, offset.y))
    }
}
