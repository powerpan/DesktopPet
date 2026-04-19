//
// InlineMarkdownBubble.swift
// 气泡 / 对话等处的轻量 Markdown：将 `**加粗**`、`*斜体*` 等内联语法转为 AttributedString。
//

import Foundation

enum InlineMarkdownBubble {
    /// 解析内联 Markdown；失败时退化为纯文本，避免模型输出半段 `**` 时整段空白。
    static func attributedDisplayString(_ source: String) -> AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let a = try? AttributedString(markdown: source, options: opts) {
            return a
        }
        return AttributedString(source)
    }

    /// CoreText 等宽近似：去掉成对 `**`，避免星号参与折行宽度（仅测量用）。
    static func plainForSizing(_ source: String) -> String {
        source.replacingOccurrences(of: "**", with: "")
    }
}
