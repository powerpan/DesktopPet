//
// AccessibilityOnboardingView.swift
// 辅助功能说明与引导：解释为何需要权限，并提供打开系统设置、重新检测等操作。
//

import AppKit
import SwiftUI

struct AccessibilityOnboardingView: View {
    @ObservedObject var permissionManager: AccessibilityPermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("需要辅助功能权限")
                .font(.title2.weight(.semibold))

            Text(
                "DesktopPet 需要「辅助功能」权限来监听全局键盘，以便小猫对你的输入做出反应。应用不会上传键入内容，事件仅在本地处理。"
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("打开系统设置") {
                    openAccessibilityPrivacyPane()
                }
                .keyboardShortcut(.defaultAction)

                Button("重新检测") {
                    permissionManager.refreshStatus(prompt: false)
                }
            }

            if permissionManager.isGranted {
                Label("已通过检测", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 480)
    }

    private func openAccessibilityPrivacyPane() {
        permissionManager.requestIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
