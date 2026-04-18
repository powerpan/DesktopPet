//
// AgentTriggerEngine.swift
// 定时、随机空闲、键盘模式、前台应用等触发后调用 DeepSeek 生成一句旁白。
//

import AppKit
import Foundation

@MainActor
final class AgentTriggerEngine: ObservableObject {
    /// 单次 `tick` 内共用的评估快照。
    private struct TriggerEvalContext {
        let now: Date
        let idle: TimeInterval
        let currentFront: String
        let frontChanged: Bool
        let tickIndex: Int
        let keyBuffer: String
    }

    private let settings: AgentSettingsStore
    private let session: AgentSessionStore
    private let client: AgentClient
    private let deskMirror: DeskMirrorModel
    private let frontWatcher: FrontmostAppWatcher

    private var tickTimer: Timer?
    private var lastUserActivityUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var lastKnownFrontApp: String = ""
    private var recentKeyBuffer: String = ""
    private var tickIndex: Int = 0

    private var isPetVisible: () -> Bool
    /// 触发旁白成功后的展示（如云气泡 + 历史记录）；与手动对话频道分离。
    private let onTriggerSpeech: ((TriggerSpeechPayload) -> Void)?

    init(
        settings: AgentSettingsStore,
        session: AgentSessionStore,
        client: AgentClient,
        deskMirror: DeskMirrorModel,
        frontWatcher: FrontmostAppWatcher,
        isPetVisible: @escaping () -> Bool,
        onTriggerSpeech: ((TriggerSpeechPayload) -> Void)? = nil
    ) {
        self.settings = settings
        self.session = session
        self.client = client
        self.deskMirror = deskMirror
        self.frontWatcher = frontWatcher
        self.isPetVisible = isPetVisible
        self.onTriggerSpeech = onTriggerSpeech
    }

    func start() {
        lastKnownFrontApp = frontWatcher.frontmostLocalizedName
        // 定时器：从未触发过时先写入当前时间，避免启动瞬间连发
        for i in settings.triggers.indices where settings.triggers[i].kind == .timer && settings.triggers[i].lastFiredAt == nil {
            var r = settings.triggers[i]
            r.lastFiredAt = Date()
            settings.triggers[i] = r
        }

        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
        frontWatcher.start()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        frontWatcher.stop()
    }

    func noteUserActivity() {
        lastUserActivityUptime = ProcessInfo.processInfo.systemUptime
    }

    func handleKeyDownForTriggers(_ event: NSEvent) {
        guard settings.keyboardTriggerMasterEnabled else { return }
        if let ch = event.charactersIgnoringModifiers, let c = ch.first {
            recentKeyBuffer.append(c)
            if recentKeyBuffer.count > 64 {
                recentKeyBuffer.removeFirst(recentKeyBuffer.count - 64)
            }
        }
        noteUserActivity()
    }

    private func tick() async {
        tickIndex += 1
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let idle = uptime - lastUserActivityUptime

        let currentFront = frontWatcher.frontmostLocalizedName
        let frontChanged = currentFront != lastKnownFrontApp
        if frontChanged {
            lastKnownFrontApp = currentFront
        }

        let ctx = TriggerEvalContext(
            now: now,
            idle: idle,
            currentFront: currentFront,
            frontChanged: frontChanged,
            tickIndex: tickIndex,
            keyBuffer: recentKeyBuffer
        )

        for i in settings.triggers.indices {
            var rule = settings.triggers[i]
            guard rule.enabled else { continue }
            if let last = rule.lastFiredAt, now.timeIntervalSince(last) < rule.cooldownSeconds {
                continue
            }
            var fired = false
            switch rule.kind {
            case .timer:
                fired = evaluateTimer(rule: &rule, ctx: ctx)
            case .randomIdle:
                fired = evaluateRandomIdle(rule: rule, ctx: ctx)
            case .keyboardPattern:
                fired = evaluateKeyboard(rule: rule, ctx: ctx)
            case .frontApp:
                fired = evaluateFrontApp(rule: rule, ctx: ctx)
            case .screenSnap, .bubbleTest:
                fired = false
            }
            if fired {
                let matchedRoute = selectMatchedRoute(rule: rule, ctx: ctx)
                rule.lastFiredAt = now
                settings.triggers[i] = rule
                await firePrologue(trigger: rule, matchedRoute: matchedRoute)
            }
        }
    }

    private func evaluateTimer(rule: inout AgentTriggerRule, ctx: TriggerEvalContext) -> Bool {
        guard rule.timerIntervalMinutes > 0 else { return false }
        let interval = TimeInterval(rule.timerIntervalMinutes * 60)
        guard let last = rule.lastFiredAt else { return false }
        guard ctx.now.timeIntervalSince(last) >= interval else { return false }
        return true
    }

    /// 每 5 秒掷一次骰子，降低刷屏概率
    private func evaluateRandomIdle(rule: AgentTriggerRule, ctx: TriggerEvalContext) -> Bool {
        guard ctx.tickIndex % 5 == 0 else { return false }
        guard isPetVisible() else { return false }
        guard ctx.idle >= TimeInterval(rule.randomIdleSeconds) else { return false }
        guard Double.random(in: 0...1) < rule.randomIdleProbability else { return false }
        return true
    }

    private func evaluateKeyboard(rule: AgentTriggerRule, ctx: TriggerEvalContext) -> Bool {
        guard settings.keyboardTriggerMasterEnabled else { return false }
        let enabledRoutes = rule.routes.filter(\.enabled)
        if enabledRoutes.isEmpty {
            let p = rule.keyboardPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return false }
            return ctx.keyBuffer.contains(p)
        }
        return enabledRoutes.contains { route in
            Self.routeIsValidForKeyboardKind(route) && conditionsSatisfied(route.conditions, rule: rule, ctx: ctx)
        }
    }

    private func evaluateFrontApp(rule: AgentTriggerRule, ctx: TriggerEvalContext) -> Bool {
        guard ctx.frontChanged else { return false }
        let enabledRoutes = rule.routes.filter(\.enabled)
        if enabledRoutes.isEmpty {
            let needle = rule.frontAppNameContains.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return false }
            return ctx.currentFront.localizedCaseInsensitiveContains(needle)
        }
        return enabledRoutes.contains { conditionsSatisfied($0.conditions, rule: rule, ctx: ctx) }
    }

    /// 键盘类路由若仅有 `.always` 会在每 tick 误触发，故要求至少包含一个 `keyboardContains`。
    private static func routeIsValidForKeyboardKind(_ route: TriggerPromptRoute) -> Bool {
        route.conditions.contains {
            if case .keyboardContains = $0 { return true }
            return false
        }
    }

    private func conditionsSatisfied(_ conditions: [TriggerRouteCondition], rule: AgentTriggerRule, ctx: TriggerEvalContext) -> Bool {
        let effective = conditions.isEmpty ? [TriggerRouteCondition.always] : conditions
        for c in effective {
            switch c {
            case .always:
                continue
            case let .keyboardContains(sub):
                let s = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return false }
                guard ctx.keyBuffer.contains(s) else { return false }
            case let .frontAppContains(sub):
                let s = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return false }
                guard ctx.currentFront.localizedCaseInsensitiveContains(s) else { return false }
            case let .idleAtLeastSeconds(sec):
                guard ctx.idle >= TimeInterval(sec) else { return false }
            case let .timerElapsedAtLeastMinutes(minutes):
                guard minutes > 0 else { continue }
                guard let last = rule.lastFiredAt else { return false }
                guard ctx.now.timeIntervalSince(last) >= TimeInterval(minutes * 60) else { return false }
            }
        }
        return true
    }

    /// 在已通过 kind 级门槛后，取 `priority` 最高的完全匹配路由。
    private func selectMatchedRoute(rule: AgentTriggerRule, ctx: TriggerEvalContext) -> TriggerPromptRoute? {
        let enabledRoutes = rule.routes.filter(\.enabled)
        guard !enabledRoutes.isEmpty else { return nil }
        let sorted = enabledRoutes.sorted { $0.priority > $1.priority }
        for route in sorted {
            if rule.kind == .keyboardPattern, !Self.routeIsValidForKeyboardKind(route) { continue }
            if conditionsSatisfied(route.conditions, rule: rule, ctx: ctx) {
                return route
            }
        }
        return nil
    }

    private static func describeRouteConditions(_ route: TriggerPromptRoute) -> String {
        if route.conditions.isEmpty { return "（无条件）" }
        return route.conditions.map { c in
            switch c {
            case .always: return "始终"
            case let .keyboardContains(s): return "按键含「\(s)」"
            case let .frontAppContains(s): return "前台含「\(s)」"
            case let .idleAtLeastSeconds(n): return "空闲≥\(n)s"
            case let .timerElapsedAtLeastMinutes(m): return "距上次≥\(m)分钟"
            }
        }.joined(separator: "；")
    }

    private func renderUserPrompt(
        trigger: AgentTriggerRule,
        matchedRoute: TriggerPromptRoute?,
        extra: String,
        keySummaryLine: String
    ) -> String {
        let rawTemplate: String = {
            if let r = matchedRoute, !r.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return r.promptTemplate
            }
            let d = trigger.defaultPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { return d }
            return AgentTriggerRule.standardPrologueTemplate
        }()
        return rawTemplate
            .replacingOccurrences(of: "{extra}", with: extra)
            .replacingOccurrences(of: "{triggerKind}", with: trigger.kind.displayName)
            .replacingOccurrences(of: "{matchedCondition}", with: matchedRoute.map { Self.describeRouteConditions($0) } ?? "")
            .replacingOccurrences(of: "{keySummary}", with: keySummaryLine)
    }

    private func firePrologue(trigger: AgentTriggerRule, matchedRoute: TriggerPromptRoute?) async {
        session.setSending(true)
        session.lastError = nil
        let key = KeychainStore.readAPIKey()
        var extra = "（系统触发：\(trigger.kind.displayName)）"
        var keySummaryLine = ""
        if settings.attachKeySummary {
            let s = deskMirror.recentKeyLabelsSummary
            if !s.isEmpty {
                let clipped = String(s.prefix(80))
                extra += " 最近键入摘要：\(clipped)"
                keySummaryLine = clipped
            }
        }
        let userLine = renderUserPrompt(trigger: trigger, matchedRoute: matchedRoute, extra: extra, keySummaryLine: keySummaryLine)
        let apiMessages: [[String: String]] = [
            ["role": "user", "content": userLine],
        ]
        do {
            let text = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: settings.systemPrompt,
                messages: apiMessages,
                temperature: settings.temperature,
                maxTokens: min(settings.maxTokens, 256)
            )
            if let onTriggerSpeech {
                onTriggerSpeech(TriggerSpeechPayload(text: text, triggerKind: trigger.kind))
            } else {
                session.appendAssistant(text)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
        session.setSending(false)
    }
}
