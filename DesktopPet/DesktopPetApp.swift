//
// DesktopPetApp.swift
// SwiftUI 应用入口：定义菜单栏场景（爪印图标）与系统「设置」面板，并把设置绑定到协调器。
//

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
            // 系统标准设置入口，与下方 Settings { } 成对
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
