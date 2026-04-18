//
// DeskMirrorModel.swift
// 桌前输入镜像：全局按键高亮示意格、鼠标垫内归一化光标；仅内存状态，不落盘。
//

import AppKit
import SwiftUI

@MainActor
final class DeskMirrorModel: ObservableObject {
    /// 辅助功能已授权时，全局 keyDown 才可用于键盘镜像。
    @Published private(set) var accessibilityKeyboardMirrorGranted = false

    @Published private(set) var highlightedKeyCode: UInt16?
    @Published private(set) var lastKeyLabel: String = ""
    /// 最近若干键的标签摘要（仅调试用，短字符串）。
    @Published private(set) var recentKeyLabelsSummary: String = ""

    /// 鼠标垫内归一化坐标，中心 (0,0)，范围约 [-1,1]；x 向右为正，y 向下为正（与 SwiftUI 一致）。
    @Published private(set) var padCursorNormalized: CGPoint = .zero

    private var recentLabels: [String] = []
    private let recentCap = 10

    func setAccessibilityKeyboardMirrorGranted(_ granted: Bool) {
        accessibilityKeyboardMirrorGranted = granted
    }

    func resetPadCursor() {
        padCursorNormalized = .zero
    }

    func consumeKeyEvent(_ event: NSEvent, mirrorKeysEnabled: Bool) {
        guard mirrorKeysEnabled else { return }
        guard accessibilityKeyboardMirrorGranted else { return }
        if event.isARepeat { return }

        let code = UInt16(event.keyCode)
        let label = PhysicalKeyLayout.displayLabel(for: event)
        highlightedKeyCode = code
        lastKeyLabel = label

        recentLabels.append(label)
        if recentLabels.count > recentCap {
            recentLabels.removeFirst(recentLabels.count - recentCap)
        }
        recentKeyLabelsSummary = recentLabels.joined(separator: " ")
    }

    /// `delta` 为屏幕坐标系（与 `NSEvent.mouseLocation` 一致）：x 右为正，y **上**为正。
    func applyMouseDeltaScreen(_ delta: CGVector) {
        let gain: CGFloat = 0.014
        let tx = padCursorNormalized.x + delta.dx * gain
        let ty = padCursorNormalized.y - delta.dy * gain
        let clampedX = max(-1, min(1, tx))
        let clampedY = max(-1, min(1, ty))
        let smooth: CGFloat = 0.38
        padCursorNormalized = CGPoint(
            x: padCursorNormalized.x + (clampedX - padCursorNormalized.x) * smooth,
            y: padCursorNormalized.y + (clampedY - padCursorNormalized.y) * smooth
        )

        // 停手后轻微回到中心（与「大幅位移跟手」并存：位移极小时多拉向 0）。
        let moved = hypot(delta.dx, delta.dy)
        if moved < 0.35 {
            let home: CGFloat = 0.06
            padCursorNormalized.x *= 1 - home
            padCursorNormalized.y *= 1 - home
        }
    }
}
