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
            mousePadBlock(width: split.padW, cell: split.cell)
        }
        .frame(width: w, alignment: .leading)
    }

    /// 键盘 + 鼠标垫宽度之和不超过 `layoutW - gap`。
    private func splitKeyboardAndPad(layoutW: CGFloat, gap: CGFloat) -> (keyboardW: CGFloat, padW: CGFloat, cell: CGFloat) {
        let w = max(1, layoutW)
        let total = max(6, w - gap)
        if total < 22 {
            let padW = max(8, total * 0.28)
            let keyboardW = total - padW
            let cell = max(2, (padW - 6 * u) / CGFloat(max(1, padCols)))
            return (keyboardW, padW, cell)
        }
        // 鼠标垫只占窄条即可，把宽度让给键盘；idealPad 上限约 7 列 + 内边距。
        let idealPad = CGFloat(padCols) * max(3, 4 * u) + 6 * u
        let padTarget = min(idealPad, total * 0.24)
        var padW = max(CGFloat(padCols) * 2 + 2 * u, min(padTarget, total - 18))
        var keyboardW = total - padW
        if keyboardW < 14 {
            keyboardW = 14
            padW = max(CGFloat(padCols) * 2 + 2 * u, total - keyboardW)
        }
        padW = min(padW, total - 12)
        keyboardW = total - padW
        let cell = max(2, (padW - 8 * u) / CGFloat(padCols))
        return (keyboardW, padW, cell)
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
                    HStack(spacing: keySpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, code in
                            keyCell(code: code)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: max(1, keyboardW))
                }
                if let code = deskMirror.highlightedKeyCode, PhysicalKeyLayout.cell(forKeyCode: code) == nil {
                    Text("其它 \(deskMirror.lastKeyLabel)")
                        .font(.system(size: max(6, 8 * u), design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !deskMirror.recentKeyLabelsSummary.isEmpty {
                    Text(deskMirror.recentKeyLabelsSummary)
                        .font(.system(size: max(6, 8 * u), design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .frame(width: max(1, keyboardW), alignment: .leading)
    }

    private func keyCell(code: UInt16) -> some View {
        let label = shortLabel(for: code)
        let on = deskMirror.highlightedKeyCode == code
            && deskMirror.accessibilityKeyboardMirrorGranted
            && settings.isDeskKeyMirrorEnabled
        let cellFont = max(6, min(10, 9 * u))
        let padH = max(0.5, 1.2 * u)
        let padV = max(0.5, 1.5 * u)
        let rowMinH = max(10, cellFont + padV * 2 + 2)
        return Text(label)
            .font(.system(size: cellFont, weight: on ? .bold : .regular, design: .monospaced))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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

    private func mousePadBlock(width padW: CGFloat, cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 2 * u) {
            Text("垫")
                .font(.system(size: max(6, 8 * u), design: .rounded))
                .foregroundStyle(.tertiary)
            padGrid(cellSize: cell, padW: padW)
        }
        .frame(width: max(1, padW), alignment: .center)
    }

    private func padGrid(cellSize: CGFloat, padW: CGFloat) -> some View {
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
                            .frame(width: cellSize, height: max(cellSize * 1.1, 7))
                            .font(.system(size: max(5, 7 * u), weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .padding(3 * u)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: max(2, 3 * u), style: .continuous))
    }
}
