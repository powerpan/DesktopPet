//
// PersonaTabView.swift
// 智能体设置 ·「人格」Tab。
//

import SwiftUI

struct PersonaTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 200)
            } header: {
                Text("系统提示（人格）")
            } footer: {
                Text("每次请求都会作为 system 消息发给模型，用来设定语气、称呼、回答语言等；对话面板里的聊天内容会接在它的后面。条件触发的旁白请求会把同一段人格文字拼在 user 消息最开头（旁白单独走一套温度与 max_tokens，见「自动化」分区），与长对话的 system 用法区分开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}
