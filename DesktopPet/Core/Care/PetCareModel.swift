//
// PetCareModel.swift
// 轻量饲养：心情/能量、每日重置、喂食与戳戳冷却、陪伴时长累计、成长衰减与统计。
//

import Combine
import Foundation
import SwiftUI

private enum PetCareKeys {
    static let state = "DesktopPet.care.state"
    static let feedCooldownSeconds = "DesktopPet.care.feedCooldownSeconds"
    static let petCooldownSeconds = "DesktopPet.care.petCooldownSeconds"
    static let growthConfig = "DesktopPet.care.growthConfig.v1"
}

@MainActor
final class PetCareModel: ObservableObject {
    @Published private(set) var state: PetCareState
    /// 喂食冷却（秒），默认 4 小时；可在「智能体设置 → 成长」调整。
    @Published var feedCooldownSeconds: Int
    /// 戳戳冷却（秒），默认 30 秒。
    @Published var petCooldownSeconds: Int
    /// 成长系统参数（独立持久化）
    @Published var growthConfig: PetGrowthConfig

    private let defaults = UserDefaults.standard
    private var companionTick: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var persistDebounceTask: Task<Void, Never>?
    private var growthRng = SplitMix64(seed: UInt64.random(in: 1 ... UInt64.max))
    private var growthClient: AgentClient?
    private weak var growthSettings: AgentSettingsStore?
    private var aiGrowthTask: Task<Void, Never>?

    private var feedCooldown: TimeInterval { TimeInterval(feedCooldownSeconds) }
    private var petCooldown: TimeInterval { TimeInterval(petCooldownSeconds) }

    private static func clampFeedCooldown(_ v: Int) -> Int { min(86_400, max(300, v)) }
    private static func clampPetCooldown(_ v: Int) -> Int { min(600, max(5, v)) }

    init() {
        if let data = defaults.data(forKey: PetCareKeys.state),
           let decoded = try? JSONDecoder().decode(PetCareState.self, from: data) {
            state = decoded
        } else {
            state = PetCareState.neutral
        }
        let feedDef = 4 * 60 * 60
        let petDef = 30
        feedCooldownSeconds = Self.clampFeedCooldown(defaults.object(forKey: PetCareKeys.feedCooldownSeconds) as? Int ?? feedDef)
        petCooldownSeconds = Self.clampPetCooldown(defaults.object(forKey: PetCareKeys.petCooldownSeconds) as? Int ?? petDef)

        if let gData = defaults.data(forKey: PetCareKeys.growthConfig),
           let g = try? JSONDecoder().decode(PetGrowthConfig.self, from: gData) {
            growthConfig = PetGrowthConfig.clamped(g)
        } else {
            growthConfig = PetGrowthConfig.default
        }

        ensureDayResetIfNeeded()

        $feedCooldownSeconds
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] v in
                guard let self else { return }
                let c = Self.clampFeedCooldown(v)
                if c != v {
                    self.feedCooldownSeconds = c
                } else {
                    self.defaults.set(c, forKey: PetCareKeys.feedCooldownSeconds)
                }
            }
            .store(in: &cancellables)
        $petCooldownSeconds
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] v in
                guard let self else { return }
                let c = Self.clampPetCooldown(v)
                if c != v {
                    self.petCooldownSeconds = c
                } else {
                    self.defaults.set(c, forKey: PetCareKeys.petCooldownSeconds)
                }
            }
            .store(in: &cancellables)

        $growthConfig
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] v in
                guard let self else { return }
                let c = PetGrowthConfig.clamped(v)
                if c != v {
                    self.growthConfig = c
                } else if let data = try? JSONEncoder().encode(c) {
                    self.defaults.set(data, forKey: PetCareKeys.growthConfig)
                }
            }
            .store(in: &cancellables)
    }

    /// 由 `AppCoordinator` 注入，用于可选 AI 成长事件。
    func configureGrowthEngine(client: AgentClient, settings: AgentSettingsStore) {
        growthClient = client
        growthSettings = settings
    }

    func startCompanionTicking(isPetVisible: @escaping () -> Bool) {
        companionTick?.invalidate()
        companionTick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.ensureDayResetIfNeeded()
                let visible = isPetVisible()
                self.runGrowthCompanionSecond(isPetVisible: visible)
            }
        }
        if let companionTick {
            RunLoop.main.add(companionTick, forMode: .common)
        }
    }

    func stopCompanionTicking() {
        companionTick?.invalidate()
        companionTick = nil
        aiGrowthTask?.cancel()
        aiGrowthTask = nil
    }

    // MARK: - 统计查询（供 UI）

    func companionMinutes(on dayKey: String) -> Int {
        PetGrowthStats.companionMinutes(on: dayKey, journal: state.companionDailyJournal)
    }

    func lastNDaysCompanionMinutes(_ n: Int) -> [(dayKey: String, minutes: Int)] {
        let keys = PetGrowthStats.lastNDayKeys(n)
        return keys.map { k in (k, companionMinutes(on: k)) }
    }

    func currentMonthSummary(calendar: Calendar = .current) -> PetGrowthMonthSummary {
        let key = PetGrowthStats.monthKey(for: Date(), calendar: calendar)
        return PetGrowthStats.summaryForMonth(yearMonthKey: key, journal: state.companionDailyJournal, calendar: calendar)
    }

    // MARK: - 内部

    private func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func ensureDayResetIfNeeded() {
        let today = dayKey()
        if state.lastResetDayKey != today {
            var s = state
            s.lastResetDayKey = today
            s.todayCompanionSeconds = 0
            s.mood = min(1, s.mood + 0.05)
            s.energy = min(1, s.energy + 0.05)
            state = s
            persistDebounced()
        }
    }

    private func runGrowthCompanionSecond(isPetVisible: Bool) {
        var s = state
        let cfg = PetGrowthConfig.clamped(growthConfig)
        let decayResult = PetDecayEngine.processHourly(state: &s, config: cfg, now: Date(), rng: &growthRng)
        for ev in decayResult.newEvents {
            applyDecayEvent(ev, to: &s)
        }
        state = s

        if let aiHour = decayResult.requestAIGrowthForHourStart {
            scheduleAIGrowthIfNeeded(contextHour: aiHour)
        }

        if isPetVisible {
            var s2 = state
            s2.todayCompanionSeconds += 1
            upsertJournal(dayKey: dayKey(), on: &s2) { row in
                row.companionSeconds += 1
            }
            state = s2
        }

        persistDebounced()
    }

    private func upsertJournal(dayKey: String, on stateRef: inout PetCareState, mutate: (inout PetCompanionDayStats) -> Void) {
        if let i = stateRef.companionDailyJournal.firstIndex(where: { $0.dayKey == dayKey }) {
            var row = stateRef.companionDailyJournal[i]
            mutate(&row)
            stateRef.companionDailyJournal[i] = row
        } else {
            var row = PetCompanionDayStats.empty(dayKey: dayKey)
            mutate(&row)
            stateRef.companionDailyJournal.append(row)
        }
        trimJournalIfNeeded(&stateRef.companionDailyJournal)
    }

    private func trimJournalIfNeeded(_ journal: inout [PetCompanionDayStats]) {
        let maxRows = 420
        guard journal.count > maxRows else { return }
        let sorted = journal.sorted { $0.dayKey < $1.dayKey }
        journal = Array(sorted.suffix(maxRows))
    }

    private func applyDecayEvent(_ ev: PetDecayEventRecord, to stateRef: inout PetCareState) {
        stateRef.mood = min(1, max(0, stateRef.mood + ev.moodDelta))
        stateRef.energy = min(1, max(0, stateRef.energy + ev.energyDelta))
        stateRef.recentDecayEvents.insert(ev, at: 0)
        if stateRef.recentDecayEvents.count > 80 {
            stateRef.recentDecayEvents = Array(stateRef.recentDecayEvents.prefix(80))
        }
        let dk = dayKey(for: ev.occurredAt)
        upsertJournal(dayKey: dk, on: &stateRef) { row in
            row.decayEventCount += 1
        }
    }

    private func scheduleAIGrowthIfNeeded(contextHour: Date) {
        let cfg = PetGrowthConfig.clamped(growthConfig)
        guard cfg.aiGrowthEventsEnabled else { return }
        if let last = state.lastAIGrowthEventAt,
           Date().timeIntervalSince(last) < cfg.aiGrowthEventsMinIntervalHours * 3600 {
            return
        }
        guard let client = growthClient, let settings = growthSettings else { return }
        guard aiGrowthTask == nil else { return }

        aiGrowthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiGrowthTask = nil }
            let recentCodes = self.state.recentDecayEvents.prefix(20).map(\.reasonCode)
            let user = PetGrowthAI.buildUserPrompt(
                hourStart: contextHour,
                mood: self.state.mood,
                energy: self.state.energy,
                recentEventCodes: recentCodes,
                localTemplateSummary: PetGrowthAI.localTemplateSummaryForPrompt()
            )
            let key = KeychainStore.readAPIKey()
            let messages: [[String: String]] = [["role": "user", "content": user]]
            do {
                let text = try await client.completeChat(
                    baseURL: settings.baseURL,
                    model: settings.model,
                    apiKey: key,
                    systemPrompt: "你只输出 JSON。不要输出任何其它字符。",
                    messages: messages,
                    temperature: 0.85,
                    maxTokens: 512
                )
                guard let parsed = PetGrowthAI.parseEvents(from: text),
                      let first = parsed.first
                else {
                    self.fallbackLocalEvent(for: contextHour)
                    return
                }
                var s = self.state
                self.applyDecayEvent(first, to: &s)
                s.lastAIGrowthEventAt = Date()
                self.state = s
                self.persistDebounced()
            } catch {
                self.fallbackLocalEvent(for: contextHour)
            }
        }
    }

    private func fallbackLocalEvent(for date: Date) {
        guard let ev = PetLocalGrowthEventPool.sampleEvent(at: date, calendar: .current, rng: &growthRng) else { return }
        var s = state
        applyDecayEvent(ev, to: &s)
        state = s
        persistDebounced()
    }

    func feedIfAllowed() -> Bool {
        if let last = state.lastFeedAt, Date().timeIntervalSince(last) < feedCooldown {
            return false
        }
        var s = state
        s.lastFeedAt = Date()
        s.mood = min(1, s.mood + 0.12)
        s.energy = min(1, s.energy + 0.15)
        upsertJournal(dayKey: dayKey(), on: &s) { row in
            row.feedCount += 1
        }
        state = s
        persistDebounced()
        return true
    }

    func petIfAllowed() -> Bool {
        if let last = state.lastPetAt, Date().timeIntervalSince(last) < petCooldown {
            return false
        }
        var s = state
        s.lastPetAt = Date()
        s.mood = min(1, s.mood + 0.06)
        upsertJournal(dayKey: dayKey(), on: &s) { row in
            row.petCount += 1
        }
        state = s
        persistDebounced()
        return true
    }

    private func persistDebounced() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistImmediate()
        }
    }

    private func persistImmediate() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: PetCareKeys.state)
        }
    }
}

/// 饲养动作成功后，拼进「饲养互动」触发器 user 模板 `{careContext}` 的说明段。
enum PetCareNarrativeContext {
    static func summaryLine(isFeed: Bool, before: PetCareState, after: PetCareState) -> String {
        let actionName = isFeed ? "喂食" : "戳一戳（抚摸）"
        func pct(_ v: Double) -> String {
            let c = min(1, max(0, v))
            return String(format: "%.0f%%", c * 100)
        }
        func deltaLine(_ d: Double) -> String {
            if abs(d) < 0.0005 { return "基本持平" }
            let pts = abs(d) * 100
            return d > 0 ? "约升 \(String(format: "%.0f", pts)) 个百分点" : "约降 \(String(format: "%.0f", pts)) 个百分点"
        }
        let moodDelta = after.mood - before.mood
        let energyDelta = after.energy - before.energy
        let companionMin = after.todayCompanionSeconds / 60
        return """
        「\(actionName)」已成功生效（非冷却拒绝）。
        心情：操作前约 \(pct(before.mood)) → 操作后约 \(pct(after.mood))（\(deltaLine(moodDelta))）。
        能量：操作前约 \(pct(before.energy)) → 操作后约 \(pct(after.energy))（\(deltaLine(energyDelta))）。
        今日在宠物窗口可见时累计陪伴约 \(companionMin) 分钟（为当前快照，供你写反应时参考，勿像报表一样对用户复读数字）。
        """
    }
}
