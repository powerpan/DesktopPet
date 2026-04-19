//
// ConversationCenterTabView.swift
// 智能体工作台 ·「对话」分区：会话与历史 + 人格。
//

import SwiftUI

struct ConversationCenterTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("对话与内容")
                    .font(.title3.weight(.semibold))
                Text("频道、历史与清理在此；下方「人格」影响长对话与条件旁白的语气。")
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
