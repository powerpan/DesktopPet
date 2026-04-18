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
        // 先启动 watcher，再用与 tick 相同的数据源对齐，避免读到尚未 `refresh` 的空串。
        frontWatcher.start()
        lastKnownFrontApp = Self.readFrontmostLocalizedName()
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
    }

    /// 与 `NSWorkspace` 同步读取当前激活应用名；勿仅用 `FrontmostAppWatcher` 缓存，部分切前台路径不会发 `didActivateApplication`。
    private static func readFrontmostLocalizedName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
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

    private func buildTriggerEvalContext(now: Date) -> TriggerEvalContext {
        let uptime = ProcessInfo.processInfo.systemUptime
        let idle = uptime - lastUserActivityUptime
        let currentFront = Self.readFrontmostLocalizedName()
        let frontChanged = currentFront != lastKnownFrontApp
        return TriggerEvalContext(
            now: now,
            idle: idle,
            currentFront: currentFront,
            frontChanged: frontChanged,
            tickIndex: tickIndex,
            keyBuffer: recentKeyBuffer
        )
    }

    /// 设置页「立即触发」：用当前表单快照走与自动触发相同的模型请求与旁白链路；不经过各 kind 的自动门槛判断。
    func forceFireTrigger(ruleSnapshot: AgentTriggerRule) async {
        guard ruleSnapshot.kind != .screenSnap else { return }
        guard let i = settings.triggers.firstIndex(where: { $0.id == ruleSnapshot.id }) else { return }
        var ruleForEval = ruleSnapshot
        ruleForEval.lastFiredAt = settings.triggers[i].lastFiredAt
        let ctx = buildTriggerEvalContext(now: Date())
        let matchedRoute = selectMatchedRouteForForceFire(rule: ruleForEval, ctx: ctx)
        let now = Date()
        var stored = settings.triggers[i]
        stored.lastFiredAt = now
        settings.triggers[i] = stored
        let careDryRun = ruleForEval.kind == .careInteraction
            ? "（以下为设置页「立即触发」试跑，未发生真实喂食或戳戳。）"
            : nil
        await firePrologue(
            trigger: ruleForEval,
            matchedRoute: matchedRoute,
            trimKeyboardBufferIfFired: false,
            careContextAppendix: careDryRun
        )
    }

    /// 饲养面板喂食/戳戳成功后：若存在已启用的「饲养互动」规则，则按冷却与旁白链路请求模型。
    func fireCareInteractionNarrative(contextLine: String) async {
        let trimmed = contextLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let i = settings.triggers.firstIndex(where: { $0.enabled && $0.kind == .careInteraction }) else { return }
        guard !session.isSending else { return }
        let now = Date()
        var stored = settings.triggers[i]
        if let last = stored.lastFiredAt, now.timeIntervalSince(last) < stored.cooldownSeconds {
            return
        }
        var ruleForEval = stored
        ruleForEval.lastFiredAt = stored.lastFiredAt
        let ctx = buildTriggerEvalContext(now: now)
        let matchedRoute = selectMatchedRouteForForceFire(rule: ruleForEval, ctx: ctx)
        stored.lastFiredAt = now
        settings.triggers[i] = stored
        await firePrologue(
            trigger: ruleForEval,
            matchedRoute: matchedRoute,
            trimKeyboardBufferIfFired: false,
            careContextAppendix: trimmed
        )
    }

    private func tick() async {
        tickIndex += 1
        let now = Date()
        let ctx = buildTriggerEvalContext(now: now)
        if ctx.frontChanged {
            lastKnownFrontApp = ctx.currentFront
        }

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
            case .screenSnap, .careInteraction:
                fired = false
            }
            if fired {
                let matchedRoute = selectMatchedRoute(rule: rule, ctx: ctx)
                rule.lastFiredAt = now
                settings.triggers[i] = rule
                await firePrologue(
                    trigger: rule,
                    matchedRoute: matchedRoute,
                    trimKeyboardBufferIfFired: rule.kind == .keyboardPattern,
                    careContextAppendix: nil
                )
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

    /// 设置页「立即触发」：先按真实快照做与自动触发相同的路由选择；若无一命中（例如前台规则在设置窗试跑、当前前台并不是 Xcode），则按优先级回退到第一条可用的启用路由，便于试跑已编辑的模板。
    private func selectMatchedRouteForForceFire(rule: AgentTriggerRule, ctx: TriggerEvalContext) -> TriggerPromptRoute? {
        if let matched = selectMatchedRoute(rule: rule, ctx: ctx) {
            return matched
        }
        let sorted = rule.routes.filter(\.enabled).sorted { $0.priority > $1.priority }
        for route in sorted {
            if rule.kind == .keyboardPattern, !Self.routeIsValidForKeyboardKind(route) { continue }
            return route
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
        keySummaryLine: String,
        careContext: String? = nil
    ) -> String {
        let rawTemplate: String = {
            if let r = matchedRoute, !r.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return r.promptTemplate
            }
            let d = trigger.defaultPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { return d }
            return AgentTriggerRule.defaultPromptTemplate(for: trigger.kind)
        }()
        let care = careContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hadCareSlot = rawTemplate.contains("{careContext}")
        var merged = rawTemplate
            .replacingOccurrences(of: "{extra}", with: extra)
            .replacingOccurrences(of: "{triggerKind}", with: trigger.kind.displayName)
            .replacingOccurrences(of: "{matchedCondition}", with: matchedRoute.map { Self.describeRouteConditions($0) } ?? "")
            .replacingOccurrences(of: "{keySummary}", with: keySummaryLine)
            .replacingOccurrences(of: "{careContext}", with: care)
        if !care.isEmpty, !hadCareSlot {
            merged += "\n\n" + care
        }
        return merged
    }

    /// 自动触发键盘旁白成功后，从按键缓冲中截掉「各匹配子串最后一次出现」的右端点及其之前内容，避免同一缓冲内重复命中。
    private func keyboardSubstringsForBufferTrim(trigger: AgentTriggerRule, matchedRoute: TriggerPromptRoute?) -> [String] {
        if let route = matchedRoute, !trigger.routes.isEmpty {
            return route.conditions.compactMap { c -> String? in
                guard case let .keyboardContains(s) = c else { return nil }
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
        }
        let p = trigger.keyboardPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? [] : [p]
    }

    private func lastRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        var slice = haystack[...]
        var found: Range<String.Index>?
        while let r = slice.range(of: needle) {
            found = r
            slice = slice[r.upperBound...]
        }
        return found
    }

    private func trimRecentKeyBufferAfterKeyboardFire(trigger: AgentTriggerRule, matchedRoute: TriggerPromptRoute?) {
        let subs = keyboardSubstringsForBufferTrim(trigger: trigger, matchedRoute: matchedRoute)
        guard !subs.isEmpty else { return }
        var maxEnd = recentKeyBuffer.startIndex
        for s in subs {
            guard let r = lastRange(of: s, in: recentKeyBuffer) else { continue }
            if r.upperBound > maxEnd { maxEnd = r.upperBound }
        }
        guard maxEnd > recentKeyBuffer.startIndex else { return }
        recentKeyBuffer = String(recentKeyBuffer[maxEnd...])
    }

    private func firePrologue(
        trigger: AgentTriggerRule,
        matchedRoute: TriggerPromptRoute?,
        trimKeyboardBufferIfFired: Bool,
        careContextAppendix: String? = nil
    ) async {
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
        let userLine = renderUserPrompt(
            trigger: trigger,
            matchedRoute: matchedRoute,
            extra: extra,
            keySummaryLine: keySummaryLine,
            careContext: careContextAppendix
        )
        let personality = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPayload: String
        if personality.isEmpty {
            userPayload = userLine
        } else {
            userPayload = "\(personality)\n\n\(userLine)"
        }
        let apiMessages: [[String: String]] = [
            ["role": "user", "content": userPayload],
        ]
        let effTemp = trigger.triggerTemperature ?? settings.triggerDefaultTemperature
        let rawMax = trigger.triggerMaxTokens ?? settings.triggerDefaultMaxTokens
        let effMax = min(max(rawMax, 32), 1024)
        do {
            let text = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: " ",
                messages: apiMessages,
                temperature: effTemp,
                maxTokens: effMax
            )
            if trimKeyboardBufferIfFired, trigger.kind == .keyboardPattern {
                trimRecentKeyBufferAfterKeyboardFire(trigger: trigger, matchedRoute: matchedRoute)
            }
            if let onTriggerSpeech {
                onTriggerSpeech(TriggerSpeechPayload(text: text, triggerKind: trigger.kind, userPrompt: userPayload))
            } else {
                session.appendAssistant(text)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
        session.setSending(false)
    }
}
