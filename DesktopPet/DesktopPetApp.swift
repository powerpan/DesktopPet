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
            Section("显示与面板") {
                Button("显示/隐藏宠物（⌘K）") {
                    appDelegate.coordinator.togglePetVisibility()
                }
                Button("显示/隐藏饲养面板") {
                    appDelegate.coordinator.toggleCareOverlay()
                }
                Button("显示/隐藏对话面板") {
                    appDelegate.coordinator.toggleChatOverlay()
                }
            }
            Section("智能体工作台") {
                Button("打开智能体工作台…") {
                    appDelegate.coordinator.presentAgentSettingsWindow()
                }
                Button("截屏并旁白一次…") {
                    appDelegate.coordinator.requestScreenSnapNarrativeFromMenu()
                }
            }
            Section("权限与帮助") {
                Button("辅助功能与权限说明…") {
                    appDelegate.coordinator.presentOnboardingWindow()
                }
            }
            Section("应用") {
                // 系统标准设置入口：仅桌宠外观与行为（穿透、巡逻、缩放等）
                SettingsLink()
                Divider()
                Button("退出 DesktopPet") {
                    NSApp.terminate(nil)
                }
            }
        }

        Settings {
            SettingsPanelView()
                .environmentObject(appDelegate.coordinator.settingsViewModel)
                .environmentObject(appDelegate.coordinator)
        }
    }
}
