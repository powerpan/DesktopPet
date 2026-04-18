//
// PetGrowthAI.swift
// 可选：调用 DeepSeek 生成「成长小事件」JSON，解析失败则返回 nil（由调用方回退本地）。
//

import Foundation

enum PetGrowthAI {
    private static let maxEvents = 2
    private static let moodClamp: ClosedRange<Double> = -0.25 ... 0
    private static let energyClamp: ClosedRange<Double> = -0.28 ... 0

    static func buildUserPrompt(
        hourStart: Date,
        mood: Double,
        energy: Double,
        recentEventCodes: [String],
        localTemplateSummary: String
    ) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let t = f.string(from: hourStart)
        let recent = recentEventCodes.prefix(12).joined(separator: ", ")
        return """
        你是 DesktopPet 的「猫猫成长事件」生成器。请根据当前状态，设计 1 条（最多 \(maxEvents) 条）**不重复**的小事件，用于轻微降低心情与/或能量（数值要小、偏轻松幽默，不要恐怖/自残/医疗诊断）。

        当前小时锚点（本地时区解释即可）：\(t)
        当前心情：\(String(format: "%.3f", mood))（0~1）
        当前能量：\(String(format: "%.3f", energy))（0~1）
        最近已出现的事件 code（尽量避免同义重复）：\(recent.isEmpty ? "（无）" : recent)

        你可参考的本地预设事件类型（可改写文案，但 reasonCode 请用 custom）：
        \(localTemplateSummary)

        **必须**只输出一个 JSON 对象，不要 Markdown，不要额外解释。JSON Schema：
        {"events":[{"reasonCode":"custom","reasonText":"中文短句，<=80字","moodDelta":-0.05,"energyDelta":-0.08}]}

        约束：
        - events 长度 1...\(maxEvents)
        - moodDelta、energyDelta 必须为负数或 0，且 moodDelta ∈ [\(moodClamp.lowerBound), \(moodClamp.upperBound)]，energyDelta ∈ [\(energyClamp.lowerBound), \(energyClamp.upperBound)]
        - reasonCode 只能是 "custom"
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
            let cleanText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
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
        missed_lunch / tummy_trouble / afternoon_slump / lonely_window / night_owl_regret / zoomies_crash / hairball_drama / stranger_doorbell
        """
    }
}
