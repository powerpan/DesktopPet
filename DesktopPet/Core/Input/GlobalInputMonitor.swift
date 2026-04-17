import AppKit

/// Registers `keyDown` monitors. Global events fire for other apps (needs Accessibility);
/// local events fire while this process is key (global monitor does not), so both are used.
@MainActor
final class GlobalInputMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var onKeyDown: ((NSEvent) -> Void)?
    var onCommandK: (() -> Void)?

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.dispatch(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in
                self.dispatch(event)
            }
            return event
        }

        if globalMonitor != nil {
            Logger.shared.info("Global keyDown monitor registered.")
        } else {
            Logger.shared.info("Global keyDown monitor unavailable until Accessibility is granted.")
        }
        if localMonitor != nil {
            Logger.shared.info("Local keyDown monitor registered.")
        }
    }

    func stop() {
        var removed = false
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            removed = true
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
            removed = true
        }
        if removed {
            Logger.shared.info("Keyboard monitors removed.")
        }
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
