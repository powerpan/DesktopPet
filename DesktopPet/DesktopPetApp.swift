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
            MenuBarExtraContent(coordinator: appDelegate.coordinator)
                .environmentObject(appDelegate.coordinator.settingsViewModel)
        }

        Settings {
            SettingsPanelView()
                .environmentObject(appDelegate.coordinator.settingsViewModel)
                .environmentObject(appDelegate.coordinator)
        }
    }
}

// MARK: - 菜单栏爪印（需注入 `SettingsViewModel` 以响应界面外观）

private struct MenuBarExtraContent: View {
    @EnvironmentObject private var settings: SettingsViewModel
    let coordinator: AppCoordinator

    var body: some View {
        Group {
            Section("显示与面板") {
                Button("显示/隐藏宠物（⌘K）") {
                    coordinator.togglePetVisibility()
                }
                Button("显示/隐藏饲养面板") {
                    coordinator.toggleCareOverlay()
                }
                Button("显示/隐藏对话面板") {
                    coordinator.toggleChatOverlay()
                }
            }
            Section("智能体工作台") {
                Button("打开智能体工作台…") {
                    coordinator.presentAgentSettingsWindow()
                }
                Button("截屏并旁白一次…") {
                    coordinator.requestScreenSnapNarrativeFromMenu()
                }
            }
            Section("权限与帮助") {
                Button("辅助功能与权限说明…") {
                    coordinator.presentOnboardingWindow()
                }
            }
            Section("应用") {
                SettingsLink()
                Divider()
                Button("退出 DesktopPet") {
                    NSApp.terminate(nil)
                }
            }
        }
        .preferredColorScheme(settings.colorSchemePreference.resolvedPreferredColorScheme)
    }
}
