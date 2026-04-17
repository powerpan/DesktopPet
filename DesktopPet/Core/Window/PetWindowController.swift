import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    private let petConfig = PetConfig.default

    init() {
        let rect = NSRect(x: 120, y: 240, width: petConfig.windowSize.width, height: petConfig.windowSize.height)
        let window = PetWindow(contentRect: rect)
        let rootView = PetContainerView()
        window.contentView = NSHostingView(rootView: rootView)
        super.init(window: window)
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setClickThrough(_ enabled: Bool) {
        window?.ignoresMouseEvents = enabled
    }
}
