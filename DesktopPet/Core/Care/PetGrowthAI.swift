//
// PetGrowthAI.swift
// 可选：调用 DeepSeek 生成「成长小事件」JSON，解析失败则返回 nil（由调用方回退本地）。
//

import Foundation

enum PetGrowthAI {
    private static let maxEvents = 2
    private static let moodClamp: ClosedRange<Double> = -0.25 ... 0
    private static let energyClamp: ClosedRange<Double> = -0.28 ... 0

    private static let creativityAngles: [String] = [
        "本轮请用「微观镜头」：灰尘、光斑、键盘缝、屏幕像素级误会其一，写得很小很具体。",
        "本轮请用「人类职场误读」：把人类开会/写代码/摸鱼翻译成猫猫能理解的荒谬版本。",
        "本轮请带一点轻科幻或伪科学比喻，但落脚仍是日常小事，不要真科幻设定长篇。",
        "本轮请写一个「谐音或冷梗」级别的笑点，别太冷到看不懂。",
        "本轮请写「邻居/路人」视角的八卦感，但主角仍是猫猫的小委屈。",
        "本轮请写「食物诈骗」：闻起来像开饭、结果不是，情绪落差要轻喜剧。",
        "本轮请写「身体小故障」：困、麻、痒、打嗝之一，不要医疗诊断语气。",
        "本轮请写「天气/光线」当反派，猫猫当无辜受害者。",
        "本轮请写「家具/家电」拟人化拌嘴一句，不要恐怖。",
        "本轮请写「平行宇宙一秒」：假如鼠标是逗猫棒、假如键盘是琴键，立刻收束回现实。",
        "本轮请写「社交翻车」：想卖萌结果社死，尺度要轻。",
        "本轮请写「时间感错位」：三分钟像三小时，或反之，夸张但可爱。",
        "本轮请写「好奇心税」：因手贱/嘴贱多付出一点心情或能量。",
        "本轮请写「人类画大饼」：承诺与兑现落差，猫猫内心吐槽一两句。",
        "本轮请写「影子/反光/回声」类小误会，不要灵异。",
    ]

    /// 供提示里轮换的「创意角标」，用 seed 稳定取一条，避免每次都随机到同一类（调用方可每次换新 seed）。
    static func creativityAngleLine(seed: Int) -> String {
        guard !creativityAngles.isEmpty else { return "" }
        let n = creativityAngles.count
        let i = ((seed % n) + n) % n
        return creativityAngles[i]
    }

    static func buildUserPrompt(
        hourStart: Date,
        mood: Double,
        energy: Double,
        recentEventCodes: [String],
        recentReasonTexts: [String],
        creativitySeed: Int,
        localTemplateSummary: String
    ) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let t = f.string(from: hourStart)
        let recentCodes = recentEventCodes.prefix(12).joined(separator: ", ")
        let textSnippets = recentReasonTexts.prefix(8).enumerated().map { i, s in
            let clip = String(s.prefix(42)).replacingOccurrences(of: "\n", with: " ")
            return "\(i + 1).「\(clip)」"
        }.joined(separator: "\n")
        let angle = creativityAngleLine(seed: creativitySeed)
        return """
        你是 DesktopPet 的「猫猫成长事件」文案生成器。请产出 1 条（最多 \(maxEvents) 条）**新鲜、具体、和最近记录明显不同**的小事件，用于轻微降低心情与/或能量（数值要小、偏轻松幽默，不要恐怖/自残/血腥/真实医疗诊断）。

        当前小时锚点（本地时区解释即可）：\(t)
        当前心情：\(String(format: "%.3f", mood))（0~1）
        当前能量：\(String(format: "%.3f", energy))（0~1）
        创作盐值 seed：\(creativitySeed)（不必在 reasonText 里写出数字，只作你脑内发散锚）

        最近事件 code（避免同 code 复读）：\(recentCodes.isEmpty ? "（无）" : recentCodes)

        最近事件原文摘要（**禁止**在情节、意象、句式上与下列任一条高度相似；请换场景、换道具、换因果）：
        \(textSnippets.isEmpty ? "（无，可自由发挥）" : textSnippets)

        本轮硬性创意指令（必须遵守其一风格走向）：\(angle)

        可参考的本地事件 code 词表（仅供联想，**禁止照抄**其句式；reasonCode 仍须为 custom）：
        \(localTemplateSummary)

        **必须**只输出一个 JSON 对象，不要 Markdown，不要额外解释。JSON Schema：
        {"events":[{"reasonCode":"custom","reasonText":"中文 1～2 句，<=100 字，细节要新","moodDelta":-0.05,"energyDelta":-0.08}]}

        约束：
        - events 长度 1...\(maxEvents)
        - moodDelta、energyDelta 必须为负数或 0，且 moodDelta ∈ [\(moodClamp.lowerBound), \(moodClamp.upperBound)]，energyDelta ∈ [\(energyClamp.lowerBound), \(energyClamp.upperBound)]
        - reasonCode 只能是 "custom"
        - reasonText 里不要出现「JSON」「moodDelta」等字段名；不要列表或分点，只要自然叙述
        """
    }

    static func parseEvents(from modelText: String) -> [PetDecayEventRecord]? {
        let trimmed = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonSlice = extractJSONObject(trimmed) else { return nil }
        guard let data = jsonSlice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["events"] as? [[String: Any]],
              !arr.isEmpty
        else { return nil }

        var out: [PetDecayEventRecord] = []
        for raw in arr.prefix(maxEvents) {
            guard let code = raw["reasonCode"] as? String, code == "custom" else { continue }
            guard let text = raw["reasonText"] as? String else { continue }
            let cleanText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
            guard !cleanText.isEmpty else { continue }
            let md0 = (raw["moodDelta"] as? NSNumber)?.doubleValue ?? (raw["moodDelta"] as? Double) ?? 0
            let ed0 = (raw["energyDelta"] as? NSNumber)?.doubleValue ?? (raw["energyDelta"] as? Double) ?? 0
            let md = clamp(md0, moodClamp)
            let ed = clamp(ed0, energyClamp)
            if md >= -1e-9, ed >= -1e-9 { continue }
            out.append(PetDecayEventRecord.make(
                reasonCode: "custom",
                reasonText: cleanText,
                moodDelta: md,
                energyDelta: ed,
                source: .ai,
                raw: trimmed
            ))
        }
        return out.isEmpty ? nil : out
    }

    private static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
        min(r.upperBound, max(r.lowerBound, v))
    }

    private static func extractJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{"),
              let end = s.lastIndex(of: "}")
        else { return nil }
        return String(s[start ... end])
    }

    static func localTemplateSummaryForPrompt() -> String {
        """
        missed_lunch / tummy_trouble / afternoon_slump / lonely_window / night_owl_regret / zoomies_crash / hairball_drama / stranger_doorbell / vacuum_neighbor / screen_cursor_chase / sunbeam_moved / cardboard_trap / treat_rattle_tease / rainy_window_mood / keyboard_warmth_hog / zoom_meeting_blep / socks_thief / plant_leaf_interest / reflection_confusion / dream_running_legs / icecube_paw / backup_snack_denied / wifi_lag_angst / dust_mote_ballet
        """
    }
}
