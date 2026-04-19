//
// SlackPetWatchCommand.swift
// Slack 入站：`!pet watch` / `!pet 盯屏` 快速解析 + 自然语言触发判定辅助。
//

import Foundation

/// 从 Slack 文本解析出的盯屏草稿（仅 OCR + 可选模型兜底，不含亮度启发式）。
struct SlackPetWatchDraft: Equatable {
    var ocrSubstring: String
    var visionUserHint: String
    var taskTitle: String
}

enum SlackPetWatchCommand {
    /// 是否值得调用模型做自然语言抽取（「盯屏」或口语「看着/盯着屏幕」、进度条类盯屏、常见英文表述）。
    static func shouldAttemptNaturalLanguageParse(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: "!pet watch", options: .caseInsensitive) != nil { return false }
        if t.range(of: "!pet 盯屏", options: .caseInsensitive) != nil { return false }
        if t.contains("盯") && (t.contains("屏") || t.contains("屏幕")) { return true }
        // 口语常写「帮我看着屏幕」而非「盯屏」，需同样走盯屏 JSON 抽取。
        if (t.contains("盯着") || t.contains("看着")) && (t.contains("屏") || t.contains("屏幕")) { return true }
        // 「帮我看屏幕」等略写
        if t.contains("看") && t.contains("屏幕") {
            let watchHints = ["帮我看", "帮你看", "看一下", "看着", "盯着", "留意", "注意", "盯"]
            if watchHints.contains(where: { t.contains($0) }) { return true }
        }
        // 进度条 / 加载条类：用户未必提「屏」，但属于盯屏能力范围
        if t.contains("进度条") || t.contains("加载条") {
            let intentHints = ["满", "走完", "完成", "好", "告诉", "提醒", "通知", "喊", "盯", "看", "帮"]
            if intentHints.contains(where: { t.contains($0) }) { return true }
        }
        let lower = t.lowercased()
        if lower.contains("watch") && (lower.contains("screen") || lower.contains("desktop")) { return true }
        if lower.contains("progress bar") || lower.contains("loading bar") { return true }
        return false
    }

    /// 解析 `!pet watch …` / `!pet 盯屏 …`；无法识别则返回 `nil`。
    static func parseQuickCommand(_ raw: String) -> SlackPetWatchDraft? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rest = strippingCommandPrefix(trimmed), !rest.isEmpty else { return nil }
        let lower = rest.lowercased()
        if lower.hasPrefix("ocr") {
            let after = rest.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !after.isEmpty else { return nil }
            if let r = after.range(of: " ask ", options: .caseInsensitive) {
                let ocr = String(after[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let ask = String(after[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ocr.isEmpty else { return nil }
                return SlackPetWatchDraft(
                    ocrSubstring: ocr,
                    visionUserHint: ask,
                    taskTitle: defaultTitle(ocr: ocr, vision: ask)
                )
            }
            return SlackPetWatchDraft(
                ocrSubstring: after,
                visionUserHint: "",
                taskTitle: defaultTitle(ocr: after, vision: "")
            )
        }
        if lower.hasPrefix("ask") {
            let after = rest.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !after.isEmpty else { return nil }
            return SlackPetWatchDraft(
                ocrSubstring: "",
                visionUserHint: after,
                taskTitle: defaultTitle(ocr: "", vision: after)
            )
        }
        return nil
    }

    private static func strippingCommandPrefix(_ trimmed: String) -> String? {
        if let r = trimmed.range(of: "!pet watch", options: .caseInsensitive) {
            return String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let r = trimmed.range(of: "!pet 盯屏", options: .caseInsensitive) {
            return String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func defaultTitle(ocr: String, vision: String) -> String {
        if !ocr.isEmpty, vision.isEmpty { return "Slack盯屏：\(ocr)" }
        if ocr.isEmpty, !vision.isEmpty { return "Slack盯屏（模型）" }
        if !ocr.isEmpty, !vision.isEmpty { return "Slack盯屏：\(ocr)" }
        return "Slack盯屏"
    }

    /// 将模型返回的 JSON 文本转为草稿；失败返回 `nil`。
    static func draftFromModelJSON(_ text: String) -> SlackPetWatchDraft? {
        let stripped = Self.stripMarkdownCodeFence(text)
        guard let data = stripped.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let create = (obj["create"] as? Bool) ?? (obj["shouldCreate"] as? Bool) ?? false
        guard create else { return nil }
        let ocr = (obj["ocrSubstring"] as? String) ?? (obj["ocr"] as? String) ?? ""
        let vision = (obj["visionUserHint"] as? String) ?? (obj["visionHint"] as? String) ?? (obj["ask"] as? String) ?? ""
        let title = (obj["taskTitle"] as? String) ?? (obj["title"] as? String) ?? ""
        let o = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = vision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !o.isEmpty || !v.isEmpty else { return nil }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return SlackPetWatchDraft(
            ocrSubstring: o,
            visionUserHint: v,
            taskTitle: t.isEmpty ? defaultTitle(ocr: o, vision: v) : t
        )
    }

    private static func stripMarkdownCodeFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = String(t.dropFirst(3))
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...])
            }
            if let end = t.range(of: "```") {
                t = String(t[..<end.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
