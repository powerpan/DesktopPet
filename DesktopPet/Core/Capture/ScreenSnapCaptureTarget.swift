//
// ScreenSnapCaptureTarget.swift
// 截屏总档位：关 / 主显示器 / 副显示器（与「隐私」下拉及 Slack 远程指令对齐）。
//

import Foundation

/// 自动化里「截屏类」总开关的三档；持久化见 `AgentSettingsStore`。
enum ScreenSnapCaptureTarget: String, CaseIterable, Identifiable, Codable, Equatable {
    case off
    case mainDisplay
    case secondaryDisplay

    var id: String { rawValue }

    var privacyMenuTitle: String {
        switch self {
        case .off: return "关"
        case .mainDisplay: return "截取主屏"
        case .secondaryDisplay: return "截取副屏"
        }
    }

    var isEnabled: Bool { self != .off }

    /// 写入 `{screenCaptureMeta}` 等摘要时的中文短语。
    var metaDisplayPhrase: String {
        switch self {
        case .off: return "关"
        case .mainDisplay: return "主显示器"
        case .secondaryDisplay: return "副显示器"
        }
    }

    /// 远程点屏回复里用的短标签。
    var shortZhLabel: String {
        switch self {
        case .off: return "关"
        case .mainDisplay: return "主屏"
        case .secondaryDisplay: return "副屏"
        }
    }
}

/// 总开关为「关」时，Slack 仅允许写入「下次按哪块物理屏截」的偏好（远程点屏等仍可能截屏）。
enum ScreenSnapSlackRemoteDisplayPick: String, CaseIterable, Codable, Equatable {
    case mainDisplay
    case secondaryDisplay
}
