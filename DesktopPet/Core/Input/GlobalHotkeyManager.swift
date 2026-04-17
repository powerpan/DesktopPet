import AppKit

@MainActor
final class GlobalHotkeyManager {
    private var monitor: Any?
    var onToggleRequested: (() -> Void)?

    func registerToggleHotkey() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isCommand = event.modifierFlags.contains(.command)
            let isK = event.charactersIgnoringModifiers?.lowercased() == "k"
            if isCommand && isK {
                self?.onToggleRequested?()
            }
        }
        Logger.shared.info("Global Cmd+K hotkey monitor registered.")
    }

    func unregisterAll() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
