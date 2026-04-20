//
// CareOverlayView.swift
// 饲养叠加层：心情、能量、今日陪伴、喂食与戳戳。
//

import SwiftUI

struct CareOverlayView: View {
    @EnvironmentObject private var care: PetCareModel
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var routeBus: AppRouteBus
    @State private var toast: String?

    private var careNarrativeEnabled: Bool {
        settings.triggers.contains { $0.kind == .careInteraction && $0.enabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("七七猫 · 饲养")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    routeBus.closeCareOverlay()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭饲养面板")
            }
            moodBar(title: "心情", value: care.state.mood)
            moodBar(title: "能量", value: care.state.energy)
            Text("今日陪伴 \(care.state.todayCompanionSeconds / 60) 分钟")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("相关配置")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        Button("成长与冷却…") {
                            routeBus.presentAgentSettingsTab(index: AgentSettingsWorkspaceTab.companion.rawValue)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("旁白与自动化…") {
                            routeBus.presentAgentSettingsTab(index: AgentSettingsWorkspaceTab.automation.rawValue)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text(careNarrativeEnabled
                        ? "「饲养互动」旁白规则已启用（在自动化分区可编辑）。"
                        : "未检测到已启用的「饲养互动」旁白规则；可在自动化分区添加或打开。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("互动成功时的猫猫反应由「饲养互动」触发器旁白请求模型生成；此处仅在操作失败时提示。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                Button("喂食") {
                    let before = care.state
                    if care.feedIfAllowed() {
                        let line = PetCareNarrativeContext.summaryLine(isFeed: true, before: before, after: care.state)
                        routeBus.careInteractionForNarrative(contextLine: line)
                        toast = nil
                    } else {
                        toast = "还在冷却哦"
                    }
                }
                Button("戳戳") {
                    let before = care.state
                    if care.petIfAllowed() {
                        let line = PetCareNarrativeContext.summaryLine(isFeed: false, before: before, after: care.state)
                        routeBus.careInteractionForNarrative(contextLine: line)
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
