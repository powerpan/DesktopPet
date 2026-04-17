import AppKit

@MainActor
final class KeyboardMonitor {
    private var monitor: Any?
    var onKeyEvent: ((NSEvent) -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.onKeyEvent?(event)
        }
        Logger.shared.info("Keyboard monitor started.")
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        Logger.shared.info("Keyboard monitor stopped.")
    }
}
