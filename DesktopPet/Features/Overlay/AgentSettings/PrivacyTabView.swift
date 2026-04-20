//
// PrivacyTabView.swift
// 智能体设置 ·「隐私」Tab。
//

import AppKit
import SwiftUI

struct PrivacyTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

    @AppStorage("DesktopPet.agent.keyboardMasterRiskAcknowledged") private var keyboardRiskAcknowledged = false
    @State private var showKeyboardRiskAlert = false
    @State private var showScreenSnapInfo = false

    var body: some View {
        Form {
            Section {
                Toggle("在对话请求中附带键入摘要", isOn: $settings.attachKeySummary)
                MarkdownInlineText(source: AgentSettingsUICopy.privacyAttachKeySummaryInline(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("请求增强（高风险）")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.privacyAttachKeySummaryFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("允许键盘模式触发", isOn: Binding(
                    get: { settings.keyboardTriggerMasterEnabled },
                    set: { newValue in
                        if newValue {
                            if keyboardRiskAcknowledged {
                                settings.keyboardTriggerMasterEnabled = true
                            } else {
                                showKeyboardRiskAlert = true
                            }
                        } else {
                            settings.keyboardTriggerMasterEnabled = false
                        }
                    }
                ))
                MarkdownInlineText(source: AgentSettingsUICopy.privacyKeyboardMasterInline(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("截屏类触发", selection: $settings.screenSnapCaptureTarget) {
                    ForEach(ScreenSnapCaptureTarget.allCases) { mode in
                        Text(mode.privacyMenuTitle).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.screenSnapCaptureTarget) { old, new in
                    if old == .off, new != .off { showScreenSnapInfo = true }
                }
                MarkdownInlineText(source: AgentSettingsUICopy.privacyScreenSnapPickerInline(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("进阶触发总开关")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.privacyAdvancedSwitchesFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .alert("键盘模式触发", isPresented: $showKeyboardRiskAlert) {
            Button("取消", role: .cancel) {}
            Button("我已了解风险") {
                keyboardRiskAcknowledged = true
                settings.keyboardTriggerMasterEnabled = true
            }
        } message: {
            MarkdownInlineText(source: AgentSettingsUICopy.privacyKeyboardRiskAlertMessage(testing: petMenuSettings.testingModeEnabled))
        }
        .alert("关于截屏类触发", isPresented: $showScreenSnapInfo) {
            Button("打开屏幕录制设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("请求系统授权") {
                ScreenCaptureService.requestScreenRecordingPermission()
            }
            Button("关闭", role: .cancel) {}
        } message: {
            MarkdownInlineText(source: AgentSettingsUICopy.privacyScreenSnapAlertMessage(testing: petMenuSettings.testingModeEnabled))
        }
    }
}
