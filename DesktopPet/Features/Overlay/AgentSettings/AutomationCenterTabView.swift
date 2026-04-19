//
// AutomationCenterTabView.swift
// 智能体工作台 ·「自动化」分区：触发器 + 隐私与高风险总开关。
//

import SwiftUI

struct AutomationCenterTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("自动化与隐私")
                    .font(.title3.weight(.semibold))
                Text("条件旁白、键盘与截屏等能力在此配置；隐私页含高风险总开关，请与触发器规则一并阅读。")
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
