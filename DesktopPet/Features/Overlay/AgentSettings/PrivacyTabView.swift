//
// PrivacyTabView.swift
// 智能体设置 ·「隐私」Tab。
//

import AppKit
import SwiftUI

struct PrivacyTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore

    @AppStorage("DesktopPet.agent.keyboardMasterRiskAcknowledged") private var keyboardRiskAcknowledged = false
    @State private var showKeyboardRiskAlert = false
    @State private var showScreenSnapInfo = false

    var body: some View {
        Form {
            Section {
                Toggle("在对话请求中附带键入摘要", isOn: $settings.attachKeySummary)
                Text("依赖桌镜的键位标签摘要，可能暴露你正在输入的大致内容；默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("请求增强（高风险）")
            } footer: {
                Text("开启后，会把桌镜里显示的「键位标签摘要」拼进长对话的系统提示或触发旁白请求的 user 内容，仅在你主动发消息或触发器触发时才会上网。")
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
                Text("总开关关闭时，所有「键盘模式」类规则都不会匹配。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("截屏类触发（总开关）", isOn: $settings.screenSnapTriggerMasterEnabled)
                    .onChange(of: settings.screenSnapTriggerMasterEnabled) { _, on in
                        if on { showScreenSnapInfo = true }
                    }
                Text("关闭后，引擎不会评估任何「截屏」规则，也不会发起截屏或图像请求。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("进阶触发总开关")
            } footer: {
                Text("键盘总闸：关闭后，所有「键盘模式」类触发器都不会匹配子串。截屏总闸：关闭后不会截屏或上传图像；开启后仍需系统「屏幕录制」权限及至少一条已启用的截屏规则。")
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
            Text("开启后，应用会监听全局按键以匹配你配置的「模式串」，用于触发智能体旁白。不会把原始键入全文写入磁盘；但仍属于敏感能力，请仅在信任本机与源码时使用。")
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
            Text("开启后，满足条件的「截屏」触发器会通过 ScreenCaptureKit 截取主显示器画面，经缩放与 JPEG 压缩后，作为多模态请求的一部分发往你在「连接」里为**当前服务商**配置的 Base URL 与模型。画面可能包含屏幕上任何可见内容；请在会议或投屏场景关闭总开关或对应规则。默认不落盘原图。若模型不支持图像，应用会尝试自动改为纯文字重试一次。")
        }
    }
}
