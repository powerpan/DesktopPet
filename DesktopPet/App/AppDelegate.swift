import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
        Logger.shared.info("DesktopPet did finish launching.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        Logger.shared.info("DesktopPet will terminate.")
    }
}
