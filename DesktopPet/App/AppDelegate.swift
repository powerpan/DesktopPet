import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("DesktopPet did finish launching.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("DesktopPet will terminate.")
    }
}
