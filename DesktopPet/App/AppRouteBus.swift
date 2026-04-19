//
// AppRouteBus.swift
// 类型化应用内路由：替代零散 NotificationCenter 调用（逐步迁移）。
//

import Combine
import Foundation

@MainActor
final class AppRouteBus: ObservableObject {
    /// 递增时，`AgentSettingsView` 应切换到 `agentSettingsTabSelectionIndex`（设置窗已打开时生效；与 UserDefaults 深链并存）。
    @Published private(set) var agentSettingsTabSelectionRevision: Int = 0
    private(set) var agentSettingsTabSelectionIndex: Int = 0

    var onCloseChatOverlay: () -> Void = {}
    var onPresentChatContinuingChannel: (UUID) -> Void = { _ in }
    var onPresentAgentSettingsTab: (Int) -> Void = { _ in }
    var onForceFireTriggerRuleJSON: (String) -> Void = { _ in }
    var onCareInteractionNarrative: (String) -> Void = { _ in }
    var onAccessibilityRecheck: () -> Void = {}

    func closeChatOverlay() {
        onCloseChatOverlay()
    }

    func presentChatContinuingChannel(id: UUID) {
        onPresentChatContinuingChannel(id)
    }

    /// `index` 为工作台分区 **0…4**（连接 / 对话 / 陪伴 / 自动化 / 集成）。
    func presentAgentSettingsTab(index: Int) {
        let hi = AgentSettingsWorkspaceTab.integrations.rawValue
        let clamped = min(hi, max(0, index))
        agentSettingsTabSelectionIndex = clamped
        agentSettingsTabSelectionRevision += 1
        onPresentAgentSettingsTab(clamped)
    }

    func forceFireTriggerRuleJSON(_ json: String) {
        onForceFireTriggerRuleJSON(json)
    }

    func careInteractionForNarrative(contextLine: String) {
        onCareInteractionNarrative(contextLine)
    }

    func requestAccessibilityRecheck() {
        onAccessibilityRecheck()
    }
}
