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
        let gap = max(2, 4 * u)
        let split = splitKeyboardAndPad(layoutW: max(1, layoutW), gap: gap)
        HStack(alignment: .top, spacing: gap) {
            keyboardBlock(width: split.keyboardW)
            mousePadBlock(width: split.padW, cell: split.cell)
        }
        .frame(width: max(1, layoutW), alignment: .leading)
    }

    /// 在总宽内分配键盘与鼠标垫，保证垫不超出右边界；鼠标格宽随 `padW` 均分。
    private func splitKeyboardAndPad(layoutW: CGFloat, gap: CGFloat) -> (keyboardW: CGFloat, padW: CGFloat, cell: CGFloat) {
        let w = max(1, layoutW)
        let idealPad = CGFloat(padCols) * max(4, 5.5 * u) + 8 * u
        let maxPad = min(idealPad, w * 0.38)
        let minPad = CGFloat(padCols) * 2.5 + 4 * u
        var padW = min(maxPad, w - gap - 28)
        padW = max(minPad, padW)
        var keyboardW = w - gap - padW
        if keyboardW < 24 {
            keyboardW = 24
            padW = max(minPad, w - gap - keyboardW)
        }
        let cell = max(2.5, (padW - 8 * u) / CGFloat(padCols))
        return (keyboardW, padW, cell)
    }

    @ViewBuilder
    private func keyboardBlock(width keyboardW: CGFloat) -> some View {
        let rowSpacing = max(3, 5 * u)
        let keySpacing = max(1, 1.5 * u)
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
                    .frame(width: keyboardW)
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
        .frame(width: keyboardW, alignment: .leading)
    }

    private func keyCell(code: UInt16) -> some View {
        let label = shortLabel(for: code)
        let on = deskMirror.highlightedKeyCode == code
            && deskMirror.accessibilityKeyboardMirrorGranted
            && settings.isDeskKeyMirrorEnabled
        let cellFont = max(7, 9 * u)
        let padH = max(1, 1.5 * u)
        let padV = max(1, 2 * u)
        let rowMinH = max(12, cellFont + padV * 2 + 4)
        return Text(label)
            .font(.system(size: cellFont, weight: on ? .bold : .regular, design: .monospaced))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .frame(minHeight: rowMinH)
            .frame(maxWidth: .infinity)
            .background(on ? Color.accentColor.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: max(2, 3 * u)))
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
        .frame(width: padW, alignment: .center)
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
                            .frame(width: cellSize, height: max(cellSize * 1.12, 8))
                            .font(.system(size: max(6, 7.5 * u), weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .padding(4 * u)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: max(2, 4 * u)))
    }
}
