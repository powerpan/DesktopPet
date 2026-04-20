//
// SessionHistoryTabView.swift
// 智能体设置 ·「会话与历史」Tab。
//

import SwiftUI

struct SessionHistoryTabView: View {
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

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
                MarkdownInlineText(source: AgentSettingsUICopy.sessionHistoryFooter(testing: petMenuSettings.testingModeEnabled))
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
