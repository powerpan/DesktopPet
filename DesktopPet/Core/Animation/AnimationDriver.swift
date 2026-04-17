import Foundation

/// Abstraction for future GIF / sprite / HEVC-alpha playback. The placeholder maps state to UI metadata.
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
