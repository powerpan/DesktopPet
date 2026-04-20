//
// TriggersTabView.swift
// 智能体设置 ·「触发器」Tab。
//

import SwiftUI

struct TriggersTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

    @State private var showNewKeyboardTriggerPrivacyHint = false

    private var triggerIntroLines: [String] {
        petMenuSettings.testingModeEnabled
            ? AgentSettingsUICopy.triggersIntroLinesTesting()
            : AgentSettingsUICopy.triggersIntroLinesUser()
    }

    var body: some View {
        Form {
            Section {
                Toggle("触发旁白也推送到 Slack（总开关）", isOn: $settings.triggerSlackNotifyMasterEnabled)
            } header: {
                Text("Slack")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.triggersSlackFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(triggerIntroLines.enumerated()), id: \.offset) { _, line in
                        MarkdownInlineText(source: line)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                HStack {
                    Text("温度 (temperature)")
                    Slider(value: $settings.triggerDefaultTemperature, in: 0 ... 1.5, step: 0.05)
                    Text(String(format: "%.2f", settings.triggerDefaultTemperature))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                Stepper("max_tokens：\(settings.triggerDefaultMaxTokens)", value: $settings.triggerDefaultMaxTokens, in: 32 ... 1024, step: 32)
            } header: {
                Text("旁白生成参数（默认）")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.triggersDefaultParamsFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                ForEach(settings.triggers) { rule in
                    TriggerRuleRow(rule: rule)
                }
                .onDelete { idx in
                    for i in idx {
                        let id = settings.triggers[i].id
                        settings.removeTrigger(id: id)
                    }
                }
                Menu("添加触发器") {
                    ForEach(AgentTriggerKind.allCases.filter { $0 != .careInteraction && $0 != .petStatAutomation && $0 != .screenWatch }) { k in
                        Button(k.displayName) {
                            settings.triggers.append(.new(kind: k))
                            if k == .keyboardPattern, !settings.keyboardTriggerMasterEnabled {
                                showNewKeyboardTriggerPrivacyHint = true
                            }
                        }
                    }
                    Button("饲养互动") {
                        settings.triggers.append(.new(kind: .careInteraction))
                    }
                    Button("数值与成长旁白") {
                        settings.triggers.append(.new(kind: .petStatAutomation))
                    }
                }
            } header: {
                Text("列表")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.triggersListFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .alert(AgentSettingsUICopy.triggersKeyboardPrivacyAlertTitle(), isPresented: $showNewKeyboardTriggerPrivacyHint) {
            Button("好的", role: .cancel) {}
        } message: {
            MarkdownInlineText(source: AgentSettingsUICopy.triggersKeyboardPrivacyAlertMessage(testing: petMenuSettings.testingModeEnabled))
        }
    }
}
