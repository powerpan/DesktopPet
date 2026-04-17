import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    let permissionManager = AccessibilityPermissionManager()
    let keyboardMonitor = KeyboardMonitor()
    let mouseTracker = MouseTracker()
    let hotkeyManager = GlobalHotkeyManager()
    let stateMachine = PetStateMachine()
    let patrolScheduler = PatrolScheduler()

    private(set) var petWindowController: PetWindowController?

    func start() {
        prepareWindow()
        wireCallbacks()
        mouseTracker.start()
        hotkeyManager.registerToggleHotkey()
        permissionManager.refreshStatus()
    }

    func stop() {
        keyboardMonitor.stop()
        mouseTracker.stop()
        hotkeyManager.unregisterAll()
    }

    private func prepareWindow() {
        guard petWindowController == nil else { return }
        let controller = PetWindowController()
        controller.showWindow(nil)
        petWindowController = controller
    }

    private func wireCallbacks() {
        permissionManager.onStatusChanged = { [weak self] isGranted in
            guard let self else { return }
            if isGranted {
                self.keyboardMonitor.start()
            } else {
                self.keyboardMonitor.stop()
            }
        }

        keyboardMonitor.onKeyEvent = { [weak self] _ in
            self?.stateMachine.handle(.keyboardInput)
        }

        mouseTracker.onInteraction = { [weak self] event in
            self?.stateMachine.handle(event)
        }
    }
}
