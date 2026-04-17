import AppKit

final class HitTestPassthroughView: NSView {
    var isPassthroughEnabled = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPassthroughEnabled ? nil : super.hitTest(point)
    }
}
