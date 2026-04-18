//
// DeskMirrorTextView.swift
// 桌前猫猫文字镜像：左侧 ANSI 示意键盘格、右侧鼠标垫与光标。
//

import SwiftUI

struct DeskMirrorTextView: View {
    @EnvironmentObject private var deskMirror: DeskMirrorModel
    @EnvironmentObject private var settings: SettingsViewModel
    @Environment(\.petCardContentScale) private var u

    private let padCols = 7
    private let padRows = 5

    var body: some View {
        HStack(alignment: .top, spacing: 6 * u) {
            keyboardBlock
            mousePadBlock
        }
        .font(.system(size: max(7, 10 * u), design: .monospaced))
        .minimumScaleFactor(0.55)
    }

    @ViewBuilder
    private var keyboardBlock: some View {
        VStack(alignment: .leading, spacing: 2 * u) {
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
                    HStack(spacing: 2 * u) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, code in
                            keyCell(code: code)
                        }
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyCell(code: UInt16) -> some View {
        let label = shortLabel(for: code)
        let on = deskMirror.highlightedKeyCode == code
            && deskMirror.accessibilityKeyboardMirrorGranted
            && settings.isDeskKeyMirrorEnabled
        let cellFont = max(6, 9 * u)
        let padH = max(1, 2 * u)
        let padV = max(0.5, 1 * u)
        return Text(label)
            .font(.system(size: cellFont, weight: on ? .bold : .regular, design: .monospaced))
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .background(on ? Color.accentColor.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 3 * u))
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

    private var mousePadBlock: some View {
        let cell = max(5, 7 * u)
        let padW = CGFloat(padCols) * cell + 8 * u
        return VStack(alignment: .center, spacing: 2 * u) {
            Text("垫")
                .font(.system(size: max(6, 8 * u), design: .rounded))
                .foregroundStyle(.tertiary)
            padGrid(cellSize: cell)
        }
        .frame(width: padW)
    }

    private func padGrid(cellSize: CGFloat) -> some View {
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
                            .frame(width: cellSize, height: cellSize * 1.15)
                            .font(.system(size: max(6, 8 * u), weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .padding(4 * u)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4 * u))
    }
}
