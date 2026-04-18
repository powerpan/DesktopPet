//
// PetDecayEngine.swift
// 按小时补算基础衰减；仅当距上次结算不超过 3 小时时才按密度触发随机/AI 事件，否则只补固定衰减。
//

import Foundation

enum PetDecayEngine {
    /// 单次唤醒最多补算的小时数，避免极端时间跳变把数值打穿（仍可多次唤醒继续补）
    private static let maxCatchUpHoursPerCall = 168
    /// `PetLocalGrowthEventPool.periodMultiplier` 峰值约 1.35；density=1 时希望每小时触发概率峰值约 0.9 → k = 0.9/1.35
    private static let randomEventProbabilityK: Double = 0.9 / 1.35
    /// 单小时随机尝试成功概率上限（仍「每整点最多一条」）
    private static let randomEventProbabilityCap: Double = 0.9

    /// 与 `processHourly` 内掷骰公式一致（**不含**「距 `lastDecayAt`≤3 小时才掷」条件）。  
    /// `date` 用当前时刻时，表示「若此刻所在本地小时被结算」时的名义概率；时段系数随小时变化。
    static func nominalHourlyRandomEventProbability(
        randomEventDensityPercent: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let pct = min(100, max(0, randomEventDensityPercent))
        let density = Double(pct) / 100.0
        let hour = calendar.component(.hour, from: date)
        let period = PetLocalGrowthEventPool.periodMultiplier(forHour: hour)
        return min(randomEventProbabilityCap, density * period * randomEventProbabilityK)
    }

    struct Result: Equatable {
        var newEvents: [PetDecayEventRecord]
        /// 本批次内最后一次处理到的小时锚点（用于 AI 文案上下文）
        var lastProcessedHourStart: Date?
        /// 若为非空，应在批次外异步尝试 AI（每批次最多一次）
        var requestAIGrowthForHourStart: Date?
    }

    /// - Parameters:
    ///   - state: 会被就地修改（心情/能量/lastDecayAt/事件与日记计数由调用方统一处理）
    ///   - now: 当前时间
    ///   - rng: 随机源
    /// - Returns: 本批次新生成事件（调用方负责 append 与 journal 计数）
    @discardableResult
    static func processHourly(
        state: inout PetCareState,
        config: PetGrowthConfig,
        now: Date,
        calendar: Calendar = .current,
        rng: inout SplitMix64
    ) -> Result {
        var newEvents: [PetDecayEventRecord] = []
        var requestAIHour: Date?
        var lastHourStart: Date?

        if state.lastDecayAt == nil {
            state.lastDecayAt = now
            return Result(newEvents: [], lastProcessedHourStart: nil, requestAIGrowthForHourStart: nil)
        }

        guard let anchor = state.lastDecayAt else {
            return Result(newEvents: [], lastProcessedHourStart: nil, requestAIGrowthForHourStart: nil)
        }

        let elapsed = now.timeIntervalSince(anchor)
        var wholeHours = Int(floor(elapsed / 3600))
        if wholeHours < 1 {
            return Result(newEvents: [], lastProcessedHourStart: nil, requestAIGrowthForHourStart: nil)
        }
        wholeHours = min(wholeHours, maxCatchUpHoursPerCall)

        /// 上次结算距今在 3 小时内才允许随机事件与 AI 标记；长时间离线只按小时扣基础心情/能量。
        let allowRandomEvents = elapsed <= 3 * 3600

        let cfg = PetGrowthConfig.clamped(config)
        let density = Double(cfg.randomEventDensityPercent) / 100.0

        for h in 0 ..< wholeHours {
            guard let hourStart = calendar.date(byAdding: .hour, value: h, to: anchor) else { continue }
            lastHourStart = hourStart
            let hourComponent = calendar.component(.hour, from: hourStart)
            let period = PetLocalGrowthEventPool.periodMultiplier(forHour: hourComponent)

            state.mood = clamp01(state.mood - cfg.moodDrainPerHour)
            state.energy = clamp01(state.energy - cfg.energyDrainPerHour)

            guard allowRandomEvents else { continue }

            let p = min(randomEventProbabilityCap, density * period * randomEventProbabilityK)
            if rng.unitDouble() < p {
                if cfg.aiGrowthEventsEnabled,
                   rng.unitDouble() < 0.22 {
                    requestAIHour = hourStart
                } else if let ev = PetLocalGrowthEventPool.sampleEvent(at: hourStart, calendar: calendar, rng: &rng) {
                    // 数值由 `PetCareModel.applyDecayEvent` 统一应用，避免双重扣减
                    newEvents.append(ev)
                }
            }
        }

        state.lastDecayAt = anchor.addingTimeInterval(Double(wholeHours) * 3600)

        return Result(
            newEvents: newEvents,
            lastProcessedHourStart: lastHourStart,
            requestAIGrowthForHourStart: requestAIHour
        )
    }

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}
