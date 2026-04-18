//
// AppDelegate.swift
// 应用委托：在启动/退出时挂接菜单栏应用策略，并启动或停止 AppCoordinator。
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅菜单栏图标，不占用 Dock
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
        Logger.shared.info("DesktopPet did finish launching.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        Logger.shared.info("DesktopPet will terminate.")
    }
}
