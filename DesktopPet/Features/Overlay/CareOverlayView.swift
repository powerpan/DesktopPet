//
// CareOverlayView.swift
// 饲养叠加层：心情、能量、今日陪伴、喂食与戳戳。
//

import SwiftUI

struct CareOverlayView: View {
    @EnvironmentObject private var care: PetCareModel
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("七七猫 · 饲养")
                .font(.headline)
            moodBar(title: "心情", value: care.state.mood)
            moodBar(title: "能量", value: care.state.energy)
            Text("今日陪伴 \(care.state.todayCompanionSeconds / 60) 分钟")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("成长详情…") {
                NotificationCenter.default.post(
                    name: .desktopPetPresentAgentSettingsTab,
                    object: nil,
                    userInfo: [DesktopPetNotificationUserInfoKey.agentSettingsTabIndex: 5]
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("互动成功时的猫猫反应由「智能体设置 → 触发器 → 饲养互动」旁白请求模型生成（若已启用该规则）；此处仅在操作失败时提示。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                Button("喂食") {
                    let before = care.state
                    if care.feedIfAllowed() {
                        let line = PetCareNarrativeContext.summaryLine(isFeed: true, before: before, after: care.state)
                        NotificationCenter.default.post(
                            name: .desktopPetCareInteractionForNarrative,
                            object: nil,
                            userInfo: [DesktopPetNotificationUserInfoKey.careContext: line]
                        )
                        toast = nil
                    } else {
                        toast = "还在冷却哦"
                    }
                }
                Button("戳戳") {
                    let before = care.state
                    if care.petIfAllowed() {
                        let line = PetCareNarrativeContext.summaryLine(isFeed: false, before: before, after: care.state)
                        NotificationCenter.default.post(
                            name: .desktopPetCareInteractionForNarrative,
                            object: nil,
                            userInfo: [DesktopPetNotificationUserInfoKey.careContext: line]
                        )
                        toast = nil
                    } else {
                        toast = "稍后再戳嘛"
                    }
                }
            }
            if let toast {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moodBar(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value)
        }
    }
}
