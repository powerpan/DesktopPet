//
// ScreenSnapCaptureTarget.swift
// 截屏总档位：关 / 主显示器 / 副显示器 / 焦点屏（与「隐私」下拉、单条截屏触发器及 Slack 远程指令对齐）。
//

import Foundation

/// 自动化里「截屏类」总开关档位；持久化见 `AgentSettingsStore`。
enum ScreenSnapCaptureTarget: String, CaseIterable, Identifiable, Codable, Equatable {
    case off
    case mainDisplay
    case secondaryDisplay
    /// 前台应用（排除本应用）主窗口所在显示器；解析规则与巡逻「焦点屏」一致。
    case focusDisplay

    var id: String { rawValue }

    var privacyMenuTitle: String {
        switch self {
        case .off: return "关"
        case .mainDisplay: return "截取主屏"
        case .secondaryDisplay: return "截取副屏"
        case .focusDisplay: return "截取焦点屏"
        }
    }

    var isEnabled: Bool { self != .off }

    /// 写入 `{screenCaptureMeta}` 等摘要时的中文短语。
    var metaDisplayPhrase: String {
        switch self {
        case .off: return "关"
        case .mainDisplay: return "主显示器"
        case .secondaryDisplay: return "副显示器"
        case .focusDisplay: return "焦点显示器"
        }
    }

    /// 远程点屏回复里用的短标签。
    var shortZhLabel: String {
        switch self {
        case .off: return "关"
        case .mainDisplay: return "主屏"
        case .secondaryDisplay: return "副屏"
        case .focusDisplay: return "焦点屏"
        }
    }
}

/// 总开关为「关」时，Slack 仅允许写入「下次按哪块物理屏截」的偏好（远程点屏等仍可能截屏）。
enum ScreenSnapSlackRemoteDisplayPick: String, CaseIterable, Codable, Equatable {
    case mainDisplay
    case secondaryDisplay
    case focusDisplay

    var zhShortLabel: String {
        switch self {
        case .mainDisplay: return "主屏"
        case .secondaryDisplay: return "副屏"
        case .focusDisplay: return "焦点屏"
        }
    }
}

/// 单条「截屏」触发器截取哪块屏；「跟随自动化」= 使用「隐私」页 `ScreenSnapCaptureTarget`（关以外的主/副/焦点）。
enum ScreenSnapTriggerDisplayChoice: String, CaseIterable, Identifiable, Codable, Equatable {
    /// 与「自动化 → 隐私」中「截屏类触发」所选一致。
    case followAgentPrivacy
    case mainDisplay
    case secondaryDisplay
    case focusDisplay

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .followAgentPrivacy: return "跟随自动化（隐私页档位）"
        case .mainDisplay: return "主屏"
        case .secondaryDisplay: return "副屏"
        case .focusDisplay: return "焦点屏"
        }
    }

    /// 触发器列表副标题用短标签。
    var compactListLabel: String {
        switch self {
        case .followAgentPrivacy: return "随隐私"
        case .mainDisplay: return "主屏"
        case .secondaryDisplay: return "副屏"
        case .focusDisplay: return "焦点屏"
        }
    }

    /// 在截屏总开关已开启（`privacy != .off`）时，解析为实际截取目标。
    func resolvedCaptureTarget(privacy: ScreenSnapCaptureTarget) -> ScreenSnapCaptureTarget {
        switch self {
        case .followAgentPrivacy: return privacy
        case .mainDisplay: return .mainDisplay
        case .secondaryDisplay: return .secondaryDisplay
        case .focusDisplay: return .focusDisplay
        }
    }
}
