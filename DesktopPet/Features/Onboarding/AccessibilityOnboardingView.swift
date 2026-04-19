//
// AccessibilityOnboardingView.swift
// 辅助功能说明与引导：解释为何需要权限，并提供打开系统设置、重新检测等操作。
//

import AppKit
import SwiftUI

struct AccessibilityOnboardingView: View {
    @ObservedObject var permissionManager: AccessibilityPermissionManager
    @EnvironmentObject private var routeBus: AppRouteBus

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

            Text(
                "若你直接打开系统设置、列表里还没有 DesktopPet：需要先由本应用向系统「登记」。请优先点下面的「打开系统设置」；若仍没有，再点「让我在列表中出现」后稍等几秒，再回到设置里查看。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("打开系统设置") {
                    openAccessibilityPrivacyPane()
                }
                .keyboardShortcut(.defaultAction)

                Button("让我在列表中出现") {
                    permissionManager.triggerAccessibilityTrustPromptForSystemListing()
                }

                Button("重新检测") {
                    routeBus.requestAccessibilityRecheck()
                }
            }

            if permissionManager.isGranted {
                Label("已通过检测", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Text(permissionManager.lastRecheckSummary)
                .id(permissionManager.recheckToken)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
    }

    private func openAccessibilityPrivacyPane() {
        permissionManager.requestIfNeeded()
        // 优先深链到「隐私与安全性 → 辅助功能」应用列表；新系统若解析失败再打开「隐私与安全性」总页，需手动点「辅助功能」。
        let specs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for spec in specs {
            if let url = URL(string: spec), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
