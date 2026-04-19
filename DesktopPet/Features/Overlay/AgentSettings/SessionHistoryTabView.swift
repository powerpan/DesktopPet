//
// SessionHistoryTabView.swift
// 智能体设置 ·「会话与历史」Tab。
//

import SwiftUI

struct SessionHistoryTabView: View {
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus

    @State private var showConversationChannelsSheet = false
    @State private var showTriggerSpeechHistorySheet = false
    @State private var showTriggerUserPromptHistorySheet = false

    var body: some View {
        Form {
            Section {
                Button("查看正式会话频道…") {
                    showConversationChannelsSheet = true
                }
                Button("查看条件触发旁白历史…") {
                    showTriggerSpeechHistorySheet = true
                }
                Button("查看触发器发给模型的请求…") {
                    showTriggerUserPromptHistorySheet = true
                }
                Button("清空当前频道消息") {
                    session.clearSession()
                }
                Button("清空条件触发旁白历史", role: .destructive) {
                    session.triggerHistory.clearAll()
                }
                Button("重置所有手动会话频道", role: .destructive) {
                    session.resetAllConversationChannelsToDefault()
                }
            } header: {
                Text("会话与历史")
            } footer: {
                Text("多会话频道与消息保存在 UserDefaults；「清空当前频道」只影响当前选中会话。「旁白历史」记录模型返回的旁白正文；「发给模型的请求」记录同一次触发里作为 user 发给大模型的全文（占位符已替换，最多约 200 条与旁白历史共用条数）。清空旁白历史会同时清空这两类展示所依赖的数据。重置会话会删除所有频道并恢复为单一空会话。在旁白历史或请求列表中可按「发送类型」（触发器种类）筛选。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showConversationChannelsSheet) {
            ConversationChannelsManagerSheet(isPresented: $showConversationChannelsSheet)
                .environmentObject(session)
                .environmentObject(routeBus)
        }
        .sheet(isPresented: $showTriggerSpeechHistorySheet) {
            TriggerSpeechHistoryListSheet(isPresented: $showTriggerSpeechHistorySheet)
                .environmentObject(session)
        }
        .sheet(isPresented: $showTriggerUserPromptHistorySheet) {
            TriggerUserPromptHistorySheet(isPresented: $showTriggerUserPromptHistorySheet)
                .environmentObject(session)
        }
    }
}
