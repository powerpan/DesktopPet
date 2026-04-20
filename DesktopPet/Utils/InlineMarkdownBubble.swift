//
// InlineMarkdownBubble.swift
// 气泡 / 对话等处的轻量 Markdown：将 `**加粗**`、`*斜体*` 等内联语法转为 AttributedString。
//

import Foundation
import SwiftUI

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

// MARK: - 设置 / 工作台表单用（多行换行 + 内联 **粗体**）

/// 将 `**…**` 等按内联 Markdown 渲染，并避免在窄 `Form` 里被单行截成省略号。
struct MarkdownInlineText: View {
    let source: String
    var font: Font = .caption

    var body: some View {
        Text(InlineMarkdownBubble.attributedDisplayString(source))
            .font(font)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
