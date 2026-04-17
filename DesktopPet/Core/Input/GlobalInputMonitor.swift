import AppKit

/// Single global `keyDown` monitor to avoid duplicate `NSEvent` registrations.
@MainActor
final class GlobalInputMonitor {
    private var monitor: Any?

    var onKeyDown: ((NSEvent) -> Void)?
    var onCommandK: (() -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.dispatch(event)
            }
        }
        if monitor != nil {
            Logger.shared.info("Global input monitor started.")
        } else {
            Logger.shared.info("Global input monitor failed to register (check Accessibility permission).")
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        Logger.shared.info("Global input monitor stopped.")
    }

    private func dispatch(_ event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "k" {
            onCommandK?()
            return
        }
        onKeyDown?(event)
    }
}
