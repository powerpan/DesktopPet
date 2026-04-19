//
// SlackPetHelpCommand.swift
// Slack 入站：识别「帮助 / help」等并返回简明集成说明文案。
//

import Foundation

enum SlackPetHelpCommand {
    /// 用户仅询问用法时返回 true；避免把「帮我点一下屏幕」等误当帮助（不含远程点屏触发词）。
    static func isHelpRequest(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let lower = t.lowercased()

        if lower.hasPrefix("!pet help") { return restMeaningless(String(t.dropFirst("!pet help".count))) }
        if lower.hasPrefix("!pet 帮助") { return restMeaningless(String(t.dropFirst("!pet 帮助".count))) }

        if ["help", "usage", "commands"].contains(lower) { return true }

        let phrases = [
            "使用说明", "指令说明", "slack 帮助", "slack帮助", "怎么用", "怎麼用", "帮助一下", "帮助", "用法", "指令", "命令",
        ]
        for p in phrases {
            if matchesPhrasePrefix(t, phrase: p) { return true }
        }
        return false
    }

    /// 发回 Slack 的简明说明（`chat.postMessage` 使用 `markdown_text`，与常见 Markdown 一致写 `**粗体**`）。
    static let integrationHelpText: String = """
    🐱 **DesktopPet × Slack 简明说明**

    • **对话同步**：在应用「连接」把 Slack 频道绑定到本地会话；开启入站/出站同步后，频道里的文字与图片会进桌宠对话，模型回复会回到对应 Slack 线程。

    • **`!pet new`**：在本频道发送可新建本地会话并绑定当前频道；可带标题，如 `!pet new 讨论`。

    • **远程点屏**：发 `!pet 点屏` / `!pet click` / 中文「远程点屏」等（见集成页完整列表）。机器人会在线程里发带坐标网格的截图；请在**同一线程**回复坐标（如 `50,50` 或 `x=0.5 y=0.5`）。需要新截图时发「继续」；可发 `继续90，62` 沿用上一张图直接再点；「结束 / 停止」退出。

    • **盯屏**：`!pet watch …` / `!pet 盯屏 …`，或用自然语言描述盯屏需求（详见「集成」说明）。

    • **本说明**：发「帮助」或 `help` 可再次查看。
    """

    private static func restMeaningless(_ rest: String) -> Bool {
        let s = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return true }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "，。！？、：；,.:!?;")).isEmpty
    }

    private static func matchesPhrasePrefix(_ t: String, phrase: String) -> Bool {
        guard t.hasPrefix(phrase) else { return false }
        if t.count == phrase.count { return true }
        guard let ch = t.dropFirst(phrase.count).first else { return true }
        return ch.isWhitespace || "，。！？、：；,.:!?;".contains(ch)
    }
}
