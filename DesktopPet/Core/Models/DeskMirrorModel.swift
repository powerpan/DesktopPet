//
// DeskMirrorModel.swift
// 桌前输入镜像：全局按键高亮示意格、鼠标垫仅四向（与 BongoCat keyboard/resources/right-keys 一致）；仅内存状态，不落盘。
//

import AppKit
import SwiftUI

/// 与参考资源 `right-keys/{Up,Down,Left,Right}Arrow.png` 对应的离散方向。
enum DeskMouseMirrorDirection: Equatable {
    case none
    case up
    case down
    case left
    case right
}

@MainActor
final class DeskMirrorModel: ObservableObject {
    /// 辅助功能已授权时，全局 keyDown 才可用于键盘镜像。
    @Published private(set) var accessibilityKeyboardMirrorGranted = false

    /// 物理按下状态（keyUp 即清除），用于与系统事件对齐。
    @Published private(set) var highlightedKeyCode: UInt16?
    /// 松键后再保持约 `presentationHoldDuration` 秒，供叠层与 nohand 底图延续「最后一键」。
    @Published private(set) var presentationHighlightedKeyCode: UInt16?
    @Published private(set) var lastKeyLabel: String = ""
    /// 最近若干键的标签摘要（仅调试用，短字符串）。
    @Published private(set) var recentKeyLabelsSummary: String = ""

    /// 鼠标位移解析出的瞬时方向（停移即 `.none`）。
    @Published private(set) var mousePadDirection: DeskMouseMirrorDirection = .none
    /// 停移后再保持约 `presentationHoldDuration` 秒，供叠层与 nohand 底图延续「最后一向」。
    @Published private(set) var presentationMouseDirection: DeskMouseMirrorDirection = .none

    private var recentLabels: [String] = []
    private let recentCap = 10

    private static let presentationHoldDuration: UInt64 = 300_000_000
    private var keyPresentationResetTask: Task<Void, Never>?
    private var mousePresentationResetTask: Task<Void, Never>?

    func setAccessibilityKeyboardMirrorGranted(_ granted: Bool) {
        accessibilityKeyboardMirrorGranted = granted
    }

    func resetMouseMirror() {
        keyPresentationResetTask?.cancel()
        keyPresentationResetTask = nil
        mousePresentationResetTask?.cancel()
        mousePresentationResetTask = nil
        mousePadDirection = .none
        presentationMouseDirection = .none
        highlightedKeyCode = nil
        presentationHighlightedKeyCode = nil
    }

    func consumeKeyEvent(_ event: NSEvent, mirrorKeysEnabled: Bool) {
        guard mirrorKeysEnabled else { return }
        guard accessibilityKeyboardMirrorGranted else { return }
        if event.isARepeat { return }

        let code = UInt16(event.keyCode)
        let label = PhysicalKeyLayout.displayLabel(for: event)
        keyPresentationResetTask?.cancel()
        keyPresentationResetTask = nil
        highlightedKeyCode = code
        presentationHighlightedKeyCode = code
        lastKeyLabel = label

        recentLabels.append(label)
        if recentLabels.count > recentCap {
            recentLabels.removeFirst(recentLabels.count - recentCap)
        }
        recentKeyLabelsSummary = recentLabels.joined(separator: " ")
    }

    func consumeKeyUpEvent(_ event: NSEvent, mirrorKeysEnabled: Bool) {
        guard mirrorKeysEnabled else { return }
        guard accessibilityKeyboardMirrorGranted else { return }
        if UInt16(event.keyCode) == highlightedKeyCode {
            highlightedKeyCode = nil
            schedulePresentationKeyClear()
        }
    }

    /// `delta` 为屏幕坐标系（与 `NSEvent.mouseLocation` 一致）：x 右为正，y **上**为正。
    func applyMouseDeltaScreen(_ delta: CGVector) {
        let moved = hypot(delta.dx, delta.dy)
        let idleThreshold: CGFloat = 0.35
        if moved < idleThreshold {
            // 采样约每 80ms 一次；若每次「静止」都重启 0.3s 任务，计时器永远不会结束。
            if mousePadDirection != .none {
                mousePadDirection = .none
                schedulePresentationMouseClear()
            }
            return
        }
        mousePresentationResetTask?.cancel()
        mousePresentationResetTask = nil
        let next: DeskMouseMirrorDirection
        if abs(delta.dx) >= abs(delta.dy) {
            next = delta.dx > 0 ? .right : .left
        } else {
            next = delta.dy > 0 ? .up : .down
        }
        mousePadDirection = next
        presentationMouseDirection = next
    }

    private func schedulePresentationKeyClear() {
        keyPresentationResetTask?.cancel()
        keyPresentationResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.presentationHoldDuration)
            guard let self, !Task.isCancelled else { return }
            self.presentationHighlightedKeyCode = nil
            self.keyPresentationResetTask = nil
        }
    }

    private func schedulePresentationMouseClear() {
        mousePresentationResetTask?.cancel()
        mousePresentationResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.presentationHoldDuration)
            guard let self, !Task.isCancelled else { return }
            self.presentationMouseDirection = .none
            self.mousePresentationResetTask = nil
        }
    }
}
