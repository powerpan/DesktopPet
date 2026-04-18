//
// PhysicalKeyLayout.swift
// ANSI 示意键盘：USB keyCode（与 NSEvent.keyCode 一致）→ 网格位置；用于桌前文字镜像高亮。
//

import AppKit

enum PhysicalKeyLayout {
    /// 各行 keyCode（十进制），大致对应 Mac ANSI 字母区与数字行。
    nonisolated static let keyboardRows: [[UInt16]] = [
        [18, 19, 20, 21, 22, 23, 24, 25, 26, 29],
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35],
        [0, 1, 2, 3, 5, 4, 38, 40, 37],
        [6, 7, 8, 9, 11, 45, 46],
    ]

    nonisolated static func cell(forKeyCode code: UInt16) -> (row: Int, col: Int)? {
        for (r, row) in keyboardRows.enumerated() {
            if let c = row.firstIndex(of: code) {
                return (r, c)
            }
        }
        return nil
    }

    static func displayLabel(for event: NSEvent) -> String {
        let code = UInt16(event.keyCode)
        if let raw = event.charactersIgnoringModifiers, let ch = raw.first {
            if ch.isLetter || ch.isNumber {
                return String(ch)
            }
            let punct = CharacterSet(charactersIn: "`-=[]\\;',./")
            if let s = ch.unicodeScalars.first, punct.contains(s) {
                return String(ch)
            }
        }
        return fallbackLabels[code] ?? "·\(code)"
    }

    private nonisolated static let fallbackLabels: [UInt16: String] = [
        49: "␣",
        36: "↩",
        48: "⇥",
        51: "⌫",
        53: "⎋",
        50: "`",
        27: "-",
        24: "=",
        33: "[",
        30: "]",
        42: "\\",
        39: "'",
        41: ";",
        43: ",",
        47: ".",
        44: "/",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        56: "⇧",
        59: "⌃",
        58: "⌥",
        55: "⌘",
        57: "⇪",
        63: "fn",
    ]
}
