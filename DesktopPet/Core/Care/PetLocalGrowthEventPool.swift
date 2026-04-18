//
// PetLocalGrowthEventPool.swift
// 预设「成长/小意外」事件：按时段加权抽样。
//

import Foundation

private struct LocalGrowthTemplate {
    let code: String
    let text: String
    let moodDelta: ClosedRange<Double>
    let energyDelta: ClosedRange<Double>
    /// 在哪些本地小时更容易出现（空 = 任意时刻都可出现）
    let preferredHours: Set<Int>?
}

enum PetLocalGrowthEventPool {
    private static let templates: [LocalGrowthTemplate] = [
        LocalGrowthTemplate(
            code: "missed_lunch",
            text: "到点没吃上饭，肚子咕咕叫，有点委屈。",
            moodDelta: -0.06 ... -0.02,
            energyDelta: -0.12 ... -0.05,
            preferredHours: Set(11 ... 14)
        ),
        LocalGrowthTemplate(
            code: "tummy_trouble",
            text: "大概是吃坏了小肚子，蔫蔫地想趴着。",
            moodDelta: -0.08 ... -0.03,
            energyDelta: -0.18 ... -0.08,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "afternoon_slump",
            text: "午后犯困，眼皮打架，能量条偷偷溜走。",
            moodDelta: -0.04 ... -0.01,
            energyDelta: -0.1 ... -0.04,
            preferredHours: Set(13 ... 17)
        ),
        LocalGrowthTemplate(
            code: "lonely_window",
            text: "窗外人来人往，猫猫独自叹气，心情略低落。",
            moodDelta: -0.07 ... -0.03,
            energyDelta: -0.05 ... -0.02,
            preferredHours: Set(16 ... 21)
        ),
        LocalGrowthTemplate(
            code: "night_owl_regret",
            text: "熬夜刷存在感，结果早上起不来，心情小崩。",
            moodDelta: -0.06 ... -0.02,
            energyDelta: -0.14 ... -0.06,
            preferredHours: Set([0, 1, 2, 23])
        ),
        LocalGrowthTemplate(
            code: "zoomies_crash",
            text: "刚才疯跑太嗨，现在电量见底，瘫成一张猫饼。",
            moodDelta: -0.02 ... 0.0,
            energyDelta: -0.15 ... -0.08,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "hairball_drama",
            text: "舔毛工程过量，咳两下，今天能量不太够用。",
            moodDelta: -0.04 ... -0.01,
            energyDelta: -0.1 ... -0.05,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "stranger_doorbell",
            text: "门铃一响，警戒拉满，紧张完就累了。",
            moodDelta: -0.05 ... -0.02,
            energyDelta: -0.08 ... -0.03,
            preferredHours: Set(9 ... 20)
        ),
    ]

    /// 时段系数：用于与「事件密度」相乘
    static func periodMultiplier(forHour hour: Int) -> Double {
        switch hour {
        case 11 ... 14: return 1.35
        case 0 ... 2, 23: return 1.15
        case 13 ... 17: return 1.1
        default: return 1.0
        }
    }

    static func sampleEvent(at date: Date, calendar: Calendar = .current, rng: inout SplitMix64) -> PetDecayEventRecord? {
        let hour = calendar.component(.hour, from: date)
        let weighted: [(LocalGrowthTemplate, Double)] = templates.compactMap { t in
            if let pref = t.preferredHours {
                guard pref.contains(hour) else { return nil }
                return (t, 1.25)
            }
            return (t, 1.0)
        }
        let pool = weighted.isEmpty ? templates.map { ($0, 1.0) } : weighted
        let total = pool.reduce(0.0) { $0 + $1.1 }
        var r = rng.unitDouble() * total
        for (tpl, w) in pool {
            r -= w
            if r <= 0 {
                let md = rng.range(tpl.moodDelta)
                let ed = rng.range(tpl.energyDelta)
                return PetDecayEventRecord.make(
                    reasonCode: tpl.code,
                    reasonText: tpl.text,
                    moodDelta: md,
                    energyDelta: ed,
                    source: .local,
                    raw: nil
                )
            }
        }
        let tpl = pool[0].0
        return PetDecayEventRecord.make(
            reasonCode: tpl.code,
            reasonText: tpl.text,
            moodDelta: rng.range(tpl.moodDelta),
            energyDelta: rng.range(tpl.energyDelta),
            source: .local,
            raw: nil
        )
    }
}

// MARK: - 轻量 PRNG（可复现、无额外依赖）

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }

    mutating func range(_ r: ClosedRange<Double>) -> Double {
        let t = unitDouble()
        return r.lowerBound + (r.upperBound - r.lowerBound) * t
    }
}
