//
// GlobalInputMonitor.swift
// 键盘监听：全局与本地 keyDown / keyUp；全局用于其他应用前台（需辅助功能），本地用于本进程前台时仍能收到按键。
//

import AppKit

@MainActor
final class GlobalInputMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyUpMonitor: Any?

    var onKeyDown: ((NSEvent) -> Void)?
    var onKeyUp: ((NSEvent) -> Void)?
    var onCommandK: (() -> Void)?

    func start() {
        guard globalMonitor == nil, localMonitor == nil, globalKeyUpMonitor == nil, localKeyUpMonitor == nil else { return }

        // 其他应用为前台时的按键（未授权时返回 nil）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.dispatch(event)
            }
        }

        // 本进程为前台时的按键（全局监听收不到）
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

        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in
                self?.dispatchKeyUp(event)
            }
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in
                self.dispatchKeyUp(event)
            }
            return event
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
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
            removed = true
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
            removed = true
        }
        if removed {
            Logger.shared.info("Keyboard monitors removed.")
        }
    }

    /// 先卸再装，用于用户刚在系统设置中打开权限后，补注册此前为 nil 的全局监听。
    func restart() {
        stop()
        start()
    }

    private func dispatch(_ event: NSEvent) {
        if isCommandK(event) {
            onCommandK?()
            return
        }
        onKeyDown?(event)
    }

    private func dispatchKeyUp(_ event: NSEvent) {
        onKeyUp?(event)
    }

    /// 优先用字符判断 ⌘K；部分键盘布局下用物理键码（ANSI K = 40）兜底。
    private func isCommandK(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        if event.charactersIgnoringModifiers?.lowercased() == "k" { return true }
        return event.keyCode == 40
    }
}
