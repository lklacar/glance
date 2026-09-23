import Foundation

/// Smooth discrete wheel ticks without accumulating a queue of animations.
public struct SmoothZoom {
    public private(set) var targetScale: CGFloat?
    private var anchor = CGPoint.zero
    public init() {}

    public static func scrollFactor(delta: CGFloat, precise: Bool) -> CGFloat {
        guard delta.isFinite else { return 1 }
        return exp(min(0.22, max(-0.22, delta * (precise ? 0.006 : 0.08))))
    }

    public mutating func retarget(factor: CGFloat, anchor: CGPoint, viewport: Viewport) {
        guard factor.isFinite, factor > 0 else { return }
        var base = targetScale ?? viewport.scale
        // A reversed wheel should immediately reverse, not finish its old motion.
        if (base > viewport.scale && factor < 1) || (base < viewport.scale && factor > 1) { base = viewport.scale }
        var target = viewport
        target.zoom(to: base * factor, anchor: anchor)
        targetScale = target.scale
        self.anchor = anchor
    }

    /// Returns true while another frame is needed. The response is time based,
    /// so 60 Hz, 120 Hz, and variable-refresh displays have the same zoom speed.
    @discardableResult public mutating func advance(seconds: TimeInterval, viewport: inout Viewport) -> Bool {
        guard let targetScale, seconds.isFinite, seconds > 0 else { return self.targetScale != nil }
        let error = log(targetScale / viewport.scale)
        let fraction = 1 - exp(-seconds / 0.035)
        let next = viewport.scale * exp(error * fraction)
        if abs(log(targetScale / next)) < 0.0005 {
            viewport.zoom(to: targetScale, anchor: anchor)
            cancel()
            return false
        }
        viewport.zoom(to: next, anchor: anchor)
        return true
    }

    public mutating func cancel() { targetScale = nil }
}
