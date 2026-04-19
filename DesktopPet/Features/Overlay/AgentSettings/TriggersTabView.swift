//
// TriggersTabView.swift
// 智能体设置 ·「触发器」Tab。
//

import SwiftUI

struct TriggersTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore

    @State private var showNewKeyboardTriggerPrivacyHint = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("触发器在满足条件时会自动请求模型写一句短旁白：写入旁白历史，并以宠窗旁云气泡展示。")
                    Text("轻点气泡会关闭气泡、以该旁白为上下文新建一个手动会话频道，并打开对话面板续聊。")
                    Text("在规则编辑页底部可点「立即触发当前触发器」，用当前表单内容向模型请求一次旁白（与自动触发相同链路），便于试跑提示语与路由。")
                    Text("「饲养互动」在喂食/戳戳成功时请求旁白（不在此列表里自动轮询）；数值摘要写入模板占位符 {careContext}。首次升级会插入一条默认规则（默认关闭），可在编辑页打开开关。")
                    Text("每条规则有独立冷却，避免刷屏。定时与随机空闲适合日常使用；键盘与前台应用属于进阶能力，请谨慎开启。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Text("仅作用于「条件触发 / 立即触发」的短旁白请求，与「连接」分区里长对话的温度、max_tokens 相互独立。各条触发器可在编辑页单独覆盖；未覆盖时使用这里的默认值。")
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
                    ForEach(AgentTriggerKind.allCases.filter { $0 != .careInteraction && $0 != .screenWatch }) { k in
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
                }
            } header: {
                Text("列表")
            } footer: {
                Text("macOS 上分组表单里通常没有「左滑删除」；请点每行右侧废纸篓图标，或在打开「编辑」后使用工具栏里的「删除」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .alert("请打开键盘模式总开关", isPresented: $showNewKeyboardTriggerPrivacyHint) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("你刚添加了「键盘模式」触发器，但「自动化」分区里「隐私」表单的「允许键盘模式触发」总开关仍为关闭，规则不会生效。请向下滚动到隐私说明并打开开关。")
        }
    }
}
