//
// ConversationCenterTabView.swift
// 智能体工作台 ·「对话」分区：会话与历史 + 人格。
//

import SwiftUI

struct ConversationCenterTabView: View {
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("对话与内容")
                    .font(.title3.weight(.semibold))
                MarkdownInlineText(source: AgentSettingsUICopy.conversationCenterSubtitle(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SessionHistoryTabView()
                PersonaTabView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }
}
