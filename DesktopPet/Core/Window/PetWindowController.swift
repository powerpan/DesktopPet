import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    private let petConfig = PetConfig.default
    private weak var passthroughRoot: PetRootContainerView?

    init(settings: SettingsViewModel, stateMachine: PetStateMachine) {
        let rect = NSRect(x: 120, y: 240, width: petConfig.windowSize.width, height: petConfig.windowSize.height)
        let window = PetWindow(contentRect: rect)
        let rootView = PetContainerView()
            .environmentObject(settings)
            .environmentObject(stateMachine)
        let root = PetRootContainerView(rootView: rootView)
        window.contentView = root
        super.init(window: window)
        shouldCascadeWindows = false
        passthroughRoot = root
        window.isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.orderFrontRegardless()
    }

    func setPassthrough(_ enabled: Bool) {
        passthroughRoot?.passthroughEnabled = enabled
        window?.isMovableByWindowBackground = !enabled
    }

    func nudgePatrolStep(in visibleFrame: CGRect) {
        guard let window else { return }
        var frame = window.frame
        let margin: CGFloat = 48
        let candidates: [CGPoint] = [
            CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin),
            CGPoint(x: visibleFrame.maxX - frame.width - margin, y: visibleFrame.minY + margin),
            CGPoint(x: visibleFrame.midX - frame.width / 2, y: visibleFrame.maxY - frame.height - margin),
        ]
        if let raw = candidates.randomElement() {
            frame.origin = ScreenGeometry.clampedOrigin(frame.size, origin: raw, in: visibleFrame, margin: margin)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    func setPetVisible(_ visible: Bool) {
        guard let window else { return }
        if visible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }
}
