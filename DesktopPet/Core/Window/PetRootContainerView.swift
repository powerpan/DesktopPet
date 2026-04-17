import AppKit
import SwiftUI

/// Hosts SwiftUI content but forwards mouse hits to windows below when ``passthroughEnabled`` is on,
/// except for a fixed top-trailing control region (matches ``SettingsFloatingButton`` layout).
final class PetRootContainerView: NSView {
    private let hostingView: NSHostingView<AnyView>

    var passthroughEnabled = true {
        didSet { needsDisplay = true }
    }

    private let controlPadding: CGFloat = 6
    private let controlSize: CGFloat = 44

    init<V: View>(rootView: V) {
        hostingView = NSHostingView(rootView: AnyView(rootView))
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    private func controlBounds(in bounds: CGRect) -> CGRect {
        let w = bounds.width
        let h = bounds.height
        let side = controlPadding + controlSize
        return CGRect(x: w - side, y: h - side, width: side, height: side)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passthroughEnabled {
            let rect = controlBounds(in: bounds)
            if rect.contains(point) {
                let local = hostingView.convert(point, from: self)
                return hostingView.hitTest(local)
            }
            return nil
        }
        let local = hostingView.convert(point, from: self)
        return hostingView.hitTest(local)
    }
}
