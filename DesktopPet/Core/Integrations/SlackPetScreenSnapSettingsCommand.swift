//
// SlackPetScreenSnapSettingsCommand.swift
// Slack 入站：解析「截屏总开关 / 仅选屏」类关键词（与 `AgentSettingsStore` 三档配合）。
//

import Foundation

enum SlackPetScreenSnapSettingsCommand {

    /// 解析结果；`nil` 表示非本类指令。
    enum Result: Equatable {
        /// `!pet screen pick main|secondary` 或中文「截屏目标主屏」等。
        case remotePickOnly(ScreenSnapSlackRemoteDisplayPick)
        /// 直接写入总档位（含关）；若当前为关且本值为 main/secondary，由调用方拒绝远程「打开」。
        case setCaptureTarget(ScreenSnapCaptureTarget)
    }

    static func parse(_ raw: String) -> Result? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()

        if lower.hasPrefix("!pet screen pick") {
            let rest = String(t.dropFirst("!pet screen pick".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if rest == "main" || rest == "primary" { return .remotePickOnly(.mainDisplay) }
            if rest == "secondary" || rest == "sub" || rest == "2" { return .remotePickOnly(.secondaryDisplay) }
            if rest == "主" || rest == "主屏" { return .remotePickOnly(.mainDisplay) }
            if rest == "副" || rest == "副屏" { return .remotePickOnly(.secondaryDisplay) }
            return nil
        }

        if lower.hasPrefix("!pet screen") {
            let rest = String(t.dropFirst("!pet screen".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if rest.isEmpty || rest == "help" || rest == "帮助" { return nil }
            if rest == "off" || rest == "关" || rest == "关闭" { return .setCaptureTarget(.off) }
            if rest == "main" || rest == "primary" { return .setCaptureTarget(.mainDisplay) }
            if rest == "secondary" || rest == "sub" || rest == "2" { return .setCaptureTarget(.secondaryDisplay) }
            if rest == "主" || rest == "主屏" { return .setCaptureTarget(.mainDisplay) }
            if rest == "副" || rest == "副屏" { return .setCaptureTarget(.secondaryDisplay) }
            if ["on", "开", "打开", "启用"].contains(rest) { return .setCaptureTarget(.mainDisplay) }
            return nil
        }

        // 中文：仅选屏（总开关为关时仍可用）
        let pickMainPhrases = ["截屏目标主屏", "远程截屏主屏", "点屏目标主屏", "远程点屏主屏", "slack截屏主屏", "slack 截屏主屏"]
        for p in pickMainPhrases where matchesWholeOrPrefixKeyword(t, phrase: p) { return .remotePickOnly(.mainDisplay) }
        let pickSecPhrases = ["截屏目标副屏", "远程截屏副屏", "点屏目标副屏", "远程点屏副屏", "slack截屏副屏", "slack 截屏副屏"]
        for p in pickSecPhrases where matchesWholeOrPrefixKeyword(t, phrase: p) { return .remotePickOnly(.secondaryDisplay) }

        // 中文：写总档位（关 / 主 / 副）
        let offPhrases = ["截屏关", "关闭截屏", "截屏总开关关", "关闭截屏总开关", "截屏关闭"]
        for p in offPhrases where matchesWholeOrPrefixKeyword(t, phrase: p) { return .setCaptureTarget(.off) }

        let mainPhrases = ["截取主屏", "截屏主屏", "截屏改主屏", "截屏切换到主屏", "截屏总开关主屏", "主屏截屏"]
        for p in mainPhrases where matchesWholeOrPrefixKeyword(t, phrase: p) { return .setCaptureTarget(.mainDisplay) }

        let secPhrases = ["截取副屏", "截屏副屏", "截屏改副屏", "截屏切换到副屏", "截屏总开关副屏", "副屏截屏"]
        for p in secPhrases where matchesWholeOrPrefixKeyword(t, phrase: p) { return .setCaptureTarget(.secondaryDisplay) }

        return nil
    }

    private static func matchesWholeOrPrefixKeyword(_ text: String, phrase: String) -> Bool {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.count >= 2, text.count >= p.count else { return false }
        if text == p { return true }
        guard text.hasPrefix(p) else { return false }
        guard let ch = text.dropFirst(p.count).first else { return true }
        return ch.isWhitespace || "，。！？、：；,.:!?;".contains(ch)
    }
}
