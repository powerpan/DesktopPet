//
// AnimationDriver.swift（PetAnimationDriver）
// 占位动画层：将来可替换为 GIF/序列帧/视频；当前把状态映射为简短标题与无障碍读屏文案。
//

import Foundation

enum PetAnimationDriver {
    static func title(for state: PetState) -> String {
        switch state {
        case .idle:
            return "待"
        case .walk:
            return "走"
        case .keyTap:
            return "敲"
        case .jump:
            return "跳"
        case .sleep:
            return "睡"
        }
    }

    static func accessibilityLabel(for state: PetState) -> String {
        switch state {
        case .idle:
            return "待机"
        case .walk:
            return "行走"
        case .keyTap:
            return "敲击"
        case .jump:
            return "跳跃"
        case .sleep:
            return "睡觉"
        }
    }
}
