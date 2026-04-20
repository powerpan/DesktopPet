//
// GrowthTabView.swift
// 智能体设置 ·「成长」Tab。
//

import SwiftUI

struct GrowthTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var petCare: PetCareModel
    @EnvironmentObject private var petMenuSettings: SettingsViewModel
    @Environment(\.desktopPetAgentClient) private var desktopPetAgentClient: AgentClient?

    @State private var growthDebugRandomPreview: String?
    @State private var growthDebugRandomTestUseAI = true
    @State private var growthDebugRandomTestBusy = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("喂食冷却")
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Picker("小时", selection: growthFeedCooldownHourBinding) {
                            ForEach(0 ... 24, id: \.self) { h in
                                Text("\(h)").tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("小时")
                        .frame(minWidth: 88)

                        Text("小时")

                        Picker("分钟", selection: growthFeedCooldownMinuteBinding) {
                            ForEach(growthFeedCooldownMinuteChoices, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("分钟")
                        .frame(minWidth: 88)
                        .disabled(growthFeedCooldownHourDisplay == 24)

                        Text("分钟")
                    }
                    Text("当前约 \(growthFeedCooldownLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper(
                    "戳戳冷却：\(petCare.petCooldownSeconds) 秒",
                    value: $petCare.petCooldownSeconds,
                    in: 5 ... 600,
                    step: 5
                )
            } header: {
                Text("猫猫互动")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.growthCatInteractFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                HStack {
                    Text("每小时能量衰减")
                    Spacer()
                    Text(String(format: "%.1f%%", petCare.growthConfig.energyDrainPerHour * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthEnergyDrainBinding,
                    in: 0 ... 0.15,
                    step: 0.002
                )
                HStack {
                    Text("每小时心情衰减")
                    Spacer()
                    Text(String(format: "%.1f%%", petCare.growthConfig.moodDrainPerHour * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthMoodDrainBinding,
                    in: 0 ... 0.12,
                    step: 0.002
                )
                HStack {
                    Text("每次喂食 · 心情")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.feedMoodGain * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthFeedMoodGainBinding,
                    in: 0 ... 0.35,
                    step: 0.005
                )
                HStack {
                    Text("每次喂食 · 能量")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.feedEnergyGain * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthFeedEnergyGainBinding,
                    in: 0 ... 0.35,
                    step: 0.005
                )
                HStack {
                    Text("每次戳戳 · 心情")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.petMoodGain * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthPetMoodGainBinding,
                    in: 0 ... 0.35,
                    step: 0.005
                )
                HStack {
                    Text("每次戳戳 · 能量")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.petEnergyGain * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthPetEnergyGainBinding,
                    in: 0 ... 0.25,
                    step: 0.005
                )
                HStack {
                    Text("随机事件密度")
                    Spacer()
                    Text(growthRandomDensityPercentAndPLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthDensityBinding,
                    in: 0 ... 100,
                    step: 1
                )
                Toggle("允许 AI 生成成长事件", isOn: growthAIEnabledBinding)
                Stepper(
                    "AI 事件最小间隔：\(String(format: "%.0f", petCare.growthConfig.aiGrowthEventsMinIntervalHours)) 小时",
                    value: growthAIMinHoursBinding,
                    in: 1 ... 48,
                    step: 1
                )
            } header: {
                Text("成长参数")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.growthParamsFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("启用数值与成长旁白", isOn: statNarrativeEnabledBinding)
                HStack {
                    Text("心情告警阈值（≤）")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.statNarrativeMoodThreshold * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: statNarrativeMoodThresholdBinding, in: 0.05 ... 0.95, step: 0.01)
                HStack {
                    Text("能量告警阈值（≤）")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.statNarrativeEnergyThreshold * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: statNarrativeEnergyThresholdBinding, in: 0.05 ... 0.95, step: 0.01)
                HStack {
                    Text("恢复回差（心情与能量均须高于「阈值+回差」才解除低值闩锁）")
                    Spacer()
                    Text(String(format: "%.0f%%", petCare.growthConfig.statNarrativeRecoveryHysteresis * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: statNarrativeRecoveryHysteresisBinding, in: 0.01 ... 0.2, step: 0.01)
                Stepper(
                    "旁白最短间隔：\(petCare.growthConfig.statNarrativeCooldownMinutes) 分钟（阈值告警与成长事件共用）",
                    value: statNarrativeCooldownMinutesBinding,
                    in: 5 ... 24 * 60,
                    step: 5
                )
            } header: {
                Text("数值旁白自动化")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.growthStatNarrativeFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                let month = petCare.currentMonthSummary()
                Text("本月（\(month.yearMonthKey)）有陪伴的天数：\(month.daysWithCompanion) 天")
                Text("本月累计陪伴：\(month.totalCompanionSeconds / 60) 分钟 · 喂食 \(month.totalFeedCount) 次 · 戳戳 \(month.totalPetCount) 次 · 成长事件 \(month.totalDecayEvents) 次")
                Text("本月有陪伴日的平均陪伴：\(month.averageCompanionMinutesPerActiveDay) 分钟/天 · 最佳连续有陪伴：\(month.bestStreakDaysWithCompanion) 天")
                Divider().padding(.vertical, 4)
                Text("近 7 天陪伴（分钟）")
                    .font(.subheadline.weight(.semibold))
                ForEach(petCare.lastNDaysCompanionMinutes(7), id: \.dayKey) { row in
                    HStack {
                        Text(row.dayKey)
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(row.minutes) 分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("统计预览")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.growthStatsPreviewFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                if petCare.state.recentDecayEvents.isEmpty {
                    Text("暂无记录")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(petCare.state.recentDecayEvents) { ev in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(ev.source == .ai ? "AI" : "本地")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(ev.source == .ai ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                                        Text(ev.reasonCode)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        Text(shortDate(ev.occurredAt))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(ev.reasonText)
                                        .font(.caption)
                                    Text("心情 \(signedPct(ev.moodDelta)) · 能量 \(signedPct(ev.energyDelta))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            } header: {
                Text("最近成长事件")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.growthRecentEventsFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if petMenuSettings.testingModeEnabled {
                Section {
                    if let d = petCare.state.lastDecayAt {
                        Text("lastDecayAt（本机时区 · 毫秒精度）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(growthDebugLocalISO8601(d))
                            .font(.caption.monospacedDigit())
                            .textSelection(.enabled)
                        Text("Unix 秒：\(Int64(d.timeIntervalSince1970))")
                            .font(.caption.monospacedDigit())
                            .textSelection(.enabled)
                        let gap = Date().timeIntervalSince(d)
                        Text("距今：\(formatGrowthDebugSeconds(gap))（\(gap <= 3 * 3600 ? "≤3 小时：真实结算可掷随机" : ">3 小时：真实结算仅固定衰减")）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("lastDecayAt：nil（尚未写入锚点）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("当前心情 \(String(format: "%.3f", petCare.state.mood)) · 能量 \(String(format: "%.3f", petCare.state.energy))（仅展示）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Toggle("试跑使用 AI（默认开：每次点击都请求模型）", isOn: $growthDebugRandomTestUseAI)
                        .disabled(growthDebugRandomTestBusy)
                    Button("随机事件试跑（不改数值 / 不改 lastDecayAt）") {
                        runGrowthDebugRandomTest()
                    }
                    .disabled(growthDebugRandomTestBusy)
                    if growthDebugRandomTestBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let growthDebugRandomPreview {
                        Text(growthDebugRandomPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("调试")
                } footer: {
                    MarkdownInlineText(source: AgentSettingsUICopy.growthDebugSectionFooter(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runGrowthDebugRandomTest() {
        if growthDebugRandomTestUseAI {
            growthDebugRandomTestBusy = true
            Task { @MainActor in
                defer { growthDebugRandomTestBusy = false }
                await runGrowthDebugAITest()
            }
        } else {
            runGrowthDebugLocalRandomTest()
        }
    }

    private func runGrowthDebugLocalRandomTest() {
        var rng = SplitMix64(seed: UInt64.random(in: 1 ... UInt64.max))
        let at = Date()
        if let ev = PetLocalGrowthEventPool.sampleEvent(at: at, calendar: .current, rng: &rng) {
            let h = Calendar.current.component(.hour, from: at)
            growthDebugRandomPreview = """
            [本地池]
            抽样时刻本地小时=\(h)
            code=\(ev.reasonCode)
            \(ev.reasonText)
            moodΔ=\(String(format: "%.4f", ev.moodDelta)) · energyΔ=\(String(format: "%.4f", ev.energyDelta))
            """
        } else {
            growthDebugRandomPreview = "（未返回事件，极少见）"
        }
    }

    private func runGrowthDebugAITest() async {
        guard let client = desktopPetAgentClient else {
            growthDebugRandomPreview = "「试跑使用 AI」已打开，但未注入 AgentClient。"
            return
        }
        let at = Date()
        let recentCodes = petCare.state.recentDecayEvents.prefix(20).map(\.reasonCode)
        let recentTexts = petCare.state.recentDecayEvents.prefix(12).map(\.reasonText)
        let creativitySeed = Int.random(in: 0 ..< 1_000_000)
        let user = PetGrowthAI.buildUserPrompt(
            hourStart: at,
            mood: petCare.state.mood,
            energy: petCare.state.energy,
            recentEventCodes: recentCodes,
            recentReasonTexts: recentTexts,
            creativitySeed: creativitySeed,
            localTemplateSummary: PetGrowthAI.localTemplateSummaryForPrompt()
        )
        let key = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider)
        let messages: [[String: String]] = [["role": "user", "content": user]]
        do {
            let text = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: "你只输出 JSON。不要输出任何其它字符。",
                messages: messages,
                temperature: 1.08,
                maxTokens: 512
            )
            if let parsed = PetGrowthAI.parseEvents(from: text), let ev = parsed.first {
                let h = Calendar.current.component(.hour, from: at)
                growthDebugRandomPreview = """
                [AI 试跑 · 已解析] seed=\(creativitySeed)
                请求时刻本地小时=\(h)
                code=\(ev.reasonCode)
                \(ev.reasonText)
                moodΔ=\(String(format: "%.4f", ev.moodDelta)) · energyΔ=\(String(format: "%.4f", ev.energyDelta))
                """
            } else {
                growthDebugRandomPreview = """
                [AI 试跑 · 解析失败]
                模型原文（截断）：
                \(String(text.prefix(800)))
                """
            }
        } catch {
            growthDebugRandomPreview = "[AI 试跑 · 请求失败]\n\(error.localizedDescription)"
        }
    }

    private func growthDebugLocalISO8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime, .withTimeZone, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func formatGrowthDebugSeconds(_ t: TimeInterval) -> String {
        if t < 120 { return String(format: "%.0f 秒", t) }
        if t < 3600 { return String(format: "%.1f 分钟", t / 60) }
        return String(format: "%.2f 小时", t / 3600)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func signedPct(_ d: Double) -> String {
        let p = d * 100
        if p >= 0 { return String(format: "+%.0f%%", p) }
        return String(format: "%.0f%%", p)
    }

    private var growthEnergyDrainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.energyDrainPerHour },
            set: { v in
                var c = petCare.growthConfig
                c.energyDrainPerHour = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthMoodDrainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.moodDrainPerHour },
            set: { v in
                var c = petCare.growthConfig
                c.moodDrainPerHour = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthFeedMoodGainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.feedMoodGain },
            set: { v in
                var c = petCare.growthConfig
                c.feedMoodGain = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthFeedEnergyGainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.feedEnergyGain },
            set: { v in
                var c = petCare.growthConfig
                c.feedEnergyGain = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthPetMoodGainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.petMoodGain },
            set: { v in
                var c = petCare.growthConfig
                c.petMoodGain = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthPetEnergyGainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.petEnergyGain },
            set: { v in
                var c = petCare.growthConfig
                c.petEnergyGain = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthRandomDensityPercentAndPLine: String {
        let pct = petCare.growthConfig.randomEventDensityPercent
        let p = PetDecayEngine.nominalHourlyRandomEventProbability(randomEventDensityPercent: pct)
        return "\(pct)%（p≈\(String(format: "%.1f", p * 100))%）"
    }

    private var growthDensityBinding: Binding<Double> {
        Binding(
            get: { Double(petCare.growthConfig.randomEventDensityPercent) },
            set: { v in
                var c = petCare.growthConfig
                c.randomEventDensityPercent = Int(v.rounded())
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthAIEnabledBinding: Binding<Bool> {
        Binding(
            get: { petCare.growthConfig.aiGrowthEventsEnabled },
            set: { v in
                var c = petCare.growthConfig
                c.aiGrowthEventsEnabled = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthAIMinHoursBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.aiGrowthEventsMinIntervalHours },
            set: { v in
                var c = petCare.growthConfig
                c.aiGrowthEventsMinIntervalHours = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var statNarrativeEnabledBinding: Binding<Bool> {
        Binding(
            get: { petCare.growthConfig.statNarrativeEnabled },
            set: { v in
                var c = petCare.growthConfig
                c.statNarrativeEnabled = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var statNarrativeMoodThresholdBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.statNarrativeMoodThreshold },
            set: { v in
                var c = petCare.growthConfig
                c.statNarrativeMoodThreshold = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var statNarrativeEnergyThresholdBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.statNarrativeEnergyThreshold },
            set: { v in
                var c = petCare.growthConfig
                c.statNarrativeEnergyThreshold = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var statNarrativeRecoveryHysteresisBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.statNarrativeRecoveryHysteresis },
            set: { v in
                var c = petCare.growthConfig
                c.statNarrativeRecoveryHysteresis = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var statNarrativeCooldownMinutesBinding: Binding<Int> {
        Binding(
            get: { petCare.growthConfig.statNarrativeCooldownMinutes },
            set: { v in
                var c = petCare.growthConfig
                c.statNarrativeCooldownMinutes = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthFeedCooldownLabel: String {
        let s = petCare.feedCooldownSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0, m > 0 { return "\(h) 小时 \(m) 分钟" }
        if h > 0 { return "\(h) 小时" }
        if m > 0 { return "\(m) 分钟" }
        return "\(s) 秒"
    }

    private func growthFeedCooldownClampedTotalMinutes() -> Int {
        min(24 * 60, max(5, petCare.feedCooldownSeconds / 60))
    }

    private func growthFeedCooldownSetTotalMinutes(_ total: Int) {
        let t = min(24 * 60, max(5, total))
        petCare.feedCooldownSeconds = t * 60
    }

    private var growthFeedCooldownHourDisplay: Int {
        growthFeedCooldownClampedTotalMinutes() / 60
    }

    private var growthFeedCooldownMinuteChoices: [Int] {
        let h = growthFeedCooldownHourDisplay
        if h == 24 { return [0] }
        if h == 0 { return Array(5 ... 59) }
        return Array(0 ... 59)
    }

    private var growthFeedCooldownHourBinding: Binding<Int> {
        Binding(
            get: { growthFeedCooldownHourDisplay },
            set: { newH in
                let tot = growthFeedCooldownClampedTotalMinutes()
                let m = tot % 60
                let newTotal: Int
                if newH == 24 {
                    newTotal = 24 * 60
                } else if newH == 0 {
                    newTotal = max(5, m)
                } else {
                    newTotal = newH * 60 + m
                }
                growthFeedCooldownSetTotalMinutes(newTotal)
            }
        )
    }

    private var growthFeedCooldownMinuteBinding: Binding<Int> {
        Binding(
            get: {
                let tot = growthFeedCooldownClampedTotalMinutes()
                let h = tot / 60
                let m = tot % 60
                if h == 24 { return 0 }
                if h == 0 { return max(5, m) }
                return m
            },
            set: { newM in
                let tot = growthFeedCooldownClampedTotalMinutes()
                let h = tot / 60
                let clampedM: Int
                if h == 0 {
                    clampedM = min(59, max(5, newM))
                } else if h == 24 {
                    clampedM = 0
                } else {
                    clampedM = min(59, max(0, newM))
                }
                growthFeedCooldownSetTotalMinutes(h * 60 + clampedM)
            }
        )
    }
}
