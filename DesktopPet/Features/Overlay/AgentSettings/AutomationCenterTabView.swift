//
// AutomationCenterTabView.swift
// 智能体工作台 ·「自动化」分区：触发器 + 隐私与高风险总开关。
//

import SwiftUI

struct AutomationCenterTabView: View {
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("自动化与隐私")
                    .font(.title3.weight(.semibold))
                MarkdownInlineText(source: AgentSettingsUICopy.automationCenterSubtitle(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TriggersTabView()
                PrivacyTabView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }
}
