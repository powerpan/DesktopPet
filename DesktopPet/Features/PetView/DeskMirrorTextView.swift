//
// DeskMirrorTextView.swift
// 桌前猫猫文字镜像：左侧 ANSI 示意键盘格、右侧鼠标垫与光标。
//

import SwiftUI

struct DeskMirrorTextView: View {
    @EnvironmentObject private var deskMirror: DeskMirrorModel
    @EnvironmentObject private var settings: SettingsViewModel
    @Environment(\.petCardContentScale) private var u
    @Environment(\.petCardLayoutInnerWidth) private var layoutW

    private let padCols = 7
    private let padRows = 5

    var body: some View {
        let w = max(1, layoutW)
        let gap = max(2, 3 * u)
        let split = splitKeyboardAndPad(layoutW: w, gap: gap)
        // 用余量定键盘宽，避免浮点舍入在 HStack 右侧留一条空。
        let keyboardW = max(12, w - gap - split.padW)
        HStack(alignment: .top, spacing: gap) {
            keyboardBlock(width: keyboardW)
            mousePadBlock(width: split.padW)
        }
        .frame(width: w, alignment: .leading)
    }

    /// 键盘 + 鼠标垫宽度之和不超过 `layoutW - gap`。
    private func splitKeyboardAndPad(layoutW: CGFloat, gap: CGFloat) -> (keyboardW: CGFloat, padW: CGFloat) {
        let w = max(1, layoutW)
        let total = max(6, w - gap)
        if total < 22 {
            let padW = max(8, total * 0.34)
            let keyboardW = total - padW
            return (keyboardW, padW)
        }
        // 鼠标垫略加宽，与 `padGrid` 左右 padding（各 3*u）用同一套算式，避免垫内右侧空一截。
        let idealPad = CGFloat(padCols) * max(3, 4 * u) + 6 * u
        let padTarget = min(idealPad, total * 0.31)
        var padW = max(CGFloat(padCols) * 2 + 2 * u, min(padTarget, total - 18))
        var keyboardW = total - padW
        if keyboardW < 14 {
            keyboardW = 14
            padW = max(CGFloat(padCols) * 2 + 2 * u, total - keyboardW)
        }
        padW = min(padW, total - 12)
        keyboardW = total - padW
        return (keyboardW, padW)
    }

    @ViewBuilder
    private func keyboardBlock(width keyboardW: CGFloat) -> some View {
        let rowSpacing = max(2, 4 * u)
        let keySpacing = max(0.5, 1.2 * u)
        VStack(alignment: .leading, spacing: rowSpacing) {
            if !settings.isDeskKeyMirrorEnabled {
                Text("已在设置中关闭按键镜像")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !deskMirror.accessibilityKeyboardMirrorGranted {
                Text("需辅助功能权限以镜像按键")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(PhysicalKeyLayout.keyboardRows.enumerated()), id: \.offset) { _, row in
                    let n = CGFloat(row.count)
                    let slotW = max(3, (keyboardW - keySpacing * max(0, n - 1)) / max(n, 1))
                    HStack(spacing: keySpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, code in
                            keyCell(code: code, slotWidth: slotW)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: max(1, keyboardW))
                }
                if !deskMirror.recentKeyLabelsSummary.isEmpty {
                    Text(deskMirror.recentKeyLabelsSummary)
                        .font(.system(size: max(6, 8 * u), design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: max(1, keyboardW), alignment: .leading)
    }

    private func keyCell(code: UInt16, slotWidth: CGFloat) -> some View {
        let label = shortLabel(for: code)
        let on = deskMirror.highlightedKeyCode == code
            && deskMirror.accessibilityKeyboardMirrorGranted
            && settings.isDeskKeyMirrorEnabled
        // 字号与内边距随「本行每键宽度」与缩放 u 双约束，避免放大/缩小时格内仍叠字。
        let fromSlot = slotWidth * 0.58
        let fromScale = 9 * u
        let cellFont = max(5, min(fromSlot, fromScale, 12))
        let padH = max(0.5, min(2 * u, slotWidth * 0.14))
        let padV = max(0.5, min(2 * u, slotWidth * 0.12))
        let rowMinH = max(9, cellFont + padV * 2 + max(1, slotWidth * 0.08))
        return Text(label)
            .font(.system(size: cellFont, weight: on ? .bold : .regular, design: .monospaced))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .frame(minHeight: rowMinH)
            .frame(maxWidth: .infinity)
            .background(on ? Color.accentColor.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: max(2, 2.5 * u)))
    }

    private func shortLabel(for code: UInt16) -> String {
        switch code {
        case 18 ... 26: return "\(code - 17)"
        case 29: return "0"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 17: return "T"
        case 16: return "Y"
        case 32: return "U"
        case 34: return "I"
        case 31: return "O"
        case 35: return "P"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 45: return "N"
        case 46: return "M"
        default: return "·"
        }
    }

    private func mousePadBlock(width padW: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 2 * u) {
            Text("垫")
                .font(.system(size: max(6, 8 * u), design: .rounded))
                .foregroundStyle(.tertiary)
            padGrid(padW: padW)
        }
        .frame(width: max(1, padW), alignment: .center)
    }

    private func padGrid(padW: CGFloat) -> some View {
        let hPadding = 3 * u * 2
        let cell = max(2, (max(1, padW) - hPadding) / CGFloat(padCols))
        let nx = max(-1, min(1, deskMirror.padCursorNormalized.x))
        let ny = max(-1, min(1, deskMirror.padCursorNormalized.y))
        let cx = (nx + 1) * 0.5 * CGFloat(padCols - 1)
        let cy = (ny + 1) * 0.5 * CGFloat(padRows - 1)
        let ix = max(0, min(padCols - 1, Int(round(cx))))
        let iy = max(0, min(padRows - 1, Int(round(cy))))

        return VStack(spacing: 0) {
            ForEach(0 ..< padRows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0 ..< padCols, id: \.self) { c in
                        Text(r == iy && c == ix ? "●" : "·")
                            .frame(width: cell, height: max(cell * 1.1, 7))
                            .font(.system(size: max(5, min(8 * u, cell * 0.85)), weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .padding(3 * u)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: max(2, 3 * u), style: .continuous))
    }
}
