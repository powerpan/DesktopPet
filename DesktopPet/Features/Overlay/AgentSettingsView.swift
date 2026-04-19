//
// AgentSettingsView.swift
// 智能体工作台：五分区任务语义；各分区内容在 `Features/Overlay/AgentSettings/`。
//

import SwiftUI

struct AgentSettingsView: View {
    @EnvironmentObject private var routeBus: AppRouteBus

    /// 上次停留的工作台分区（0…4），跨重启保留。
    @AppStorage("DesktopPet.ui.agentSettingsSelectedTab") private var selectedSettingsTab = 0

    private static let pendingAgentSettingsTabKeyV2 = "DesktopPet.ui.pendingAgentSettingsTab.v2"
    private static let pendingAgentSettingsTabKeyLegacy = "DesktopPet.ui.pendingAgentSettingsTab"

    var body: some View {
        TabView(selection: $selectedSettingsTab) {
            ConnectionTabView()
                .tabItem { Label("连接", systemImage: "link") }
                .tag(AgentSettingsWorkspaceTab.connection.rawValue)
            ConversationCenterTabView()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
                .tag(AgentSettingsWorkspaceTab.conversation.rawValue)
            GrowthTabView()
                .tabItem { Label("陪伴", systemImage: "heart.circle") }
                .tag(AgentSettingsWorkspaceTab.companion.rawValue)
            AutomationCenterTabView()
                .tabItem { Label("自动化", systemImage: "bolt.shield") }
                .tag(AgentSettingsWorkspaceTab.automation.rawValue)
            IntegrationsTabView()
                .tabItem { Label("集成", systemImage: "puzzlepiece.extension") }
                .tag(AgentSettingsWorkspaceTab.integrations.rawValue)
        }
        .frame(minWidth: 520, minHeight: 560)
        .padding(12)
        .onAppear {
            AgentSettingsWorkspaceTab.migrateSelectedTabIfNeeded(currentSelection: &selectedSettingsTab)
            let hi = AgentSettingsWorkspaceTab.integrations.rawValue
            if !(AgentSettingsWorkspaceTab.connection.rawValue ... hi).contains(selectedSettingsTab) {
                selectedSettingsTab = 0
            }
            if let v = UserDefaults.standard.object(forKey: Self.pendingAgentSettingsTabKeyV2) as? Int {
                UserDefaults.standard.removeObject(forKey: Self.pendingAgentSettingsTabKeyV2)
                let layoutV = UserDefaults.standard.integer(forKey: AgentSettingsWorkspaceTab.storageLayoutVersionKey)
                if layoutV >= AgentSettingsWorkspaceTab.layoutVersionV1FiveTabs {
                    let hi = AgentSettingsWorkspaceTab.integrations.rawValue
                    selectedSettingsTab = min(hi, max(0, v))
                } else {
                    selectedSettingsTab = AgentSettingsWorkspaceTab.workspaceIndex(fromLegacySevenTabIndex: v)
                }
            } else if let legacy = UserDefaults.standard.object(forKey: Self.pendingAgentSettingsTabKeyLegacy) as? Int {
                UserDefaults.standard.removeObject(forKey: Self.pendingAgentSettingsTabKeyLegacy)
                selectedSettingsTab = AgentSettingsWorkspaceTab.workspaceIndex(fromLegacySevenTabIndex: legacy)
            }
        }
        .onChange(of: routeBus.agentSettingsTabSelectionRevision) { _, _ in
            selectedSettingsTab = routeBus.agentSettingsTabSelectionIndex
        }
    }
}
