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

    /// Keeps a window fully inside ``visibleFrame`` (AppKit coordinates, origin bottom-left).
    static func clampedOrigin(_ windowSize: CGSize, origin: CGPoint, in visibleFrame: CGRect, margin: CGFloat) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - windowSize.width - margin
        let maxY = visibleFrame.maxY - windowSize.height - margin
        if maxX < minX || maxY < minY {
            return CGPoint(x: minX, y: minY)
        }
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }
}
