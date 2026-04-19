//
// SlackPetRemoteClickCommand.swift
// Slack 远程点屏：`!pet click` / `!pet 点屏`、中文触发词列表，与用户坐标回复解析。
//

import Foundation

enum SlackPetRemoteClickCommand {
    /// 发起远程点屏：保留 `!pet click` / `!pet 点屏`，并支持一批中文关键词（整句等值或关键词后接空白/常见标点）。
    static func isStartCommand(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("!pet click") || lower.hasPrefix("!pet 点屏") {
            return true
        }

        for kw in chineseRemoteClickStartKeywords {
            if matchesChineseStartKeyword(trimmed, keyword: kw) {
                return true
            }
        }
        return false
    }

    /// 中文触发词（越长越优先在逻辑里先排，避免短词误伤；此处已按长度降序）。
    private static let chineseRemoteClickStartKeywords: [String] = [
        "屏幕远程点一下",
        "帮忙远程点一下屏",
        "猫猫帮忙点一下屏",
        "远程点一下屏幕",
        "帮忙点一下屏幕",
        "帮点一下屏幕",
        "远程点一下屏",
        "屏幕远程点击",
        "屏幕远程点屏",
        "猫猫远程点击",
        "猫猫远程点屏",
        "远程帮点屏幕",
        "远程帮点一下",
        "远程点击屏幕",
        "远程点屏一下",
        "帮忙点屏幕",
        "帮忙点一下",
        "帮点屏幕",
        "远程点击",
        "远程点屏",
        "点屏远程",
        "点一下屏",
    ]

    /// 整句等于关键词，或以前缀开头且紧随其后的字符为空白/常见全角半角标点/句末。
    private static func matchesChineseStartKeyword(_ text: String, keyword: String) -> Bool {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kw.count >= 2, text.count >= kw.count else { return false }
        if text == kw { return true }
        guard text.hasPrefix(kw) else { return false }
        let endIdx = text.index(text.startIndex, offsetBy: kw.count)
        guard endIdx < text.endIndex else { return true }
        let next = text[endIdx]
        if next.isWhitespace { return true }
        return "，。！？、：；,.:!?;".contains(next)
    }

    /// 解析用户坐标：支持 `50,50` / `50, 50` / `x=50 y=30` / `x:0.5 y:0.5`。
    /// - Returns: `(normX, normY)` 均为 0…1（左上为原点），若无法解析则 nil。
    static func parseCoordinateReply(_ raw: String) -> (Double, Double)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var xStr: String?
        var yStr: String?

        if let r = try? NSRegularExpression(pattern: #"x\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)"#, options: .caseInsensitive),
           let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           m.numberOfRanges > 1,
           let rr = Range(m.range(at: 1), in: s) {
            xStr = String(s[rr])
        }
        if let r = try? NSRegularExpression(pattern: #"y\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)"#, options: .caseInsensitive),
           let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           m.numberOfRanges > 1,
           let rr = Range(m.range(at: 1), in: s) {
            yStr = String(s[rr])
        }

        if xStr == nil || yStr == nil {
            let parts = s.split(whereSeparator: { ",;，、 \t".contains($0) }).map(String.init).filter { !$0.isEmpty }
            if parts.count >= 2, let a = Double(parts[0]), let b = Double(parts[1]) {
                return normalizePair(a, b)
            }
            return nil
        }

        guard let xs = xStr, let ys = yStr, let xv = Double(xs), let yv = Double(ys) else { return nil }
        return normalizePair(xv, yv)
    }

    /// 0-100 标尺或 0-1 直接归一化。
    private static func normalizePair(_ x: Double, _ y: Double) -> (Double, Double)? {
        func norm(_ v: Double) -> Double? {
            if v >= 0, v <= 1 { return v }
            if v >= 0, v <= 100 { return v / 100.0 }
            return nil
        }
        guard let nx = norm(x), let ny = norm(y) else { return nil }
        return (nx, ny)
    }

    #if DEBUG
    /// 轻量解析不变量（无 XCTest 目标时仍可在 Debug 构建中尽早发现回归）。
    static func runSanityChecks() {
        assert(isStartCommand("!pet click"))
        assert(isStartCommand("!PET 点屏"))
        assert(isStartCommand("远程点屏"))
        assert(isStartCommand("远程点屏，谢谢"))
        assert(isStartCommand("帮忙点一下屏幕"))
        assert(!isStartCommand("远程点屏谢谢")) // 关键词后须为空白/标点
        assert(!isStartCommand("pet click"))
        assert(!isStartCommand("点屏设置"))
        guard let a = parseCoordinateReply("50,50") else { assertionFailure(); return }
        assert(abs(a.0 - 0.5) < 0.001 && abs(a.1 - 0.5) < 0.001)
        guard let b = parseCoordinateReply("x=0.25 y=0.75") else { assertionFailure(); return }
        assert(abs(b.0 - 0.25) < 0.001 && abs(b.1 - 0.75) < 0.001)
        assert(parseCoordinateReply("120,50") == nil)
        assert(parseCoordinateReply("x=101 y=0.5") == nil)
    }
    #endif
}
