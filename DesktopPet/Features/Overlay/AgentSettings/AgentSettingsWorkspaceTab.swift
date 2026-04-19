//
// AgentSettingsWorkspaceTab.swift
// 智能体工作台：五分区任务语义（连接 / 对话 / 陪伴 / 自动化 / 集成）与旧版 7 Tab 索引迁移。
//

import Foundation

/// 工作台分区（0…4），用于 `TabView` 与 `AppRouteBus.presentAgentSettingsTab`。
enum AgentSettingsWorkspaceTab: Int, CaseIterable {
    case connection = 0
    case conversation = 1
    case companion = 2
    case automation = 3
    case integrations = 4

    static let storageLayoutVersionKey = "DesktopPet.ui.agentSettingsTabLayoutVersion"
    static let layoutVersionV1FiveTabs = 1

    /// 将**旧版 7 Tab**（0=连接 … 6=集成）映射到当前工作台分区。
    static func workspaceIndex(fromLegacySevenTabIndex legacy: Int) -> Int {
        let c = min(6, max(0, legacy))
        switch c {
        case 0: return 0
        case 1, 2: return 1
        case 3, 4: return 3
        case 5: return 2
        case 6: return 4
        default: return 0
        }
    }

    /// 首次升级到五分区布局时，迁移 `@AppStorage` 中保存的旧选中 Tab。
    static func migrateSelectedTabIfNeeded(currentSelection: inout Int) {
        let defaults = UserDefaults.standard
        let v = defaults.integer(forKey: storageLayoutVersionKey)
        guard v < layoutVersionV1FiveTabs else {
            if !(connection.rawValue ... integrations.rawValue).contains(currentSelection) {
                currentSelection = min(integrations.rawValue, max(0, currentSelection))
            }
            return
        }
        currentSelection = workspaceIndex(fromLegacySevenTabIndex: currentSelection)
        defaults.set(layoutVersionV1FiveTabs, forKey: storageLayoutVersionKey)
    }
}
