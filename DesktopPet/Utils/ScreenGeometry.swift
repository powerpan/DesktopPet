import AppKit
import CoreGraphics

enum ScreenGeometry {
    static func visibleFrameContainingMouse() -> CGRect {
        let mousePoint = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(mousePoint) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? .zero
    }

    static func clampedPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }
}
