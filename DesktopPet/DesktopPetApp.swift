import AppKit
import SwiftUI

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("DesktopPet", systemImage: "pawprint") {
            Button("显示/隐藏宠物（⌘K）") {
                appDelegate.coordinator.togglePetVisibility()
            }
            Button("辅助功能与权限说明…") {
                appDelegate.coordinator.presentOnboardingWindow()
            }
            SettingsLink()
            Divider()
            Button("退出 DesktopPet") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsPanelView()
                .environmentObject(appDelegate.coordinator.settingsViewModel)
        }
    }
}
