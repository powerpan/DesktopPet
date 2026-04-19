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
    /// 截屏旁白异步管线（与 `session.isSending` 一起防止并发抓屏/请求）。
    private var screenSnapPipelineTask: Task<Void, Never>?

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
        if ruleSnapshot.kind == .screenSnap {
            guard let idx = settings.triggers.firstIndex(where: { $0.id == ruleSnapshot.id }) else { return }
            guard settings.screenSnapTriggerMasterEnabled else {
                session.lastError = "请先在「隐私」Tab 打开「截屏类触发（总开关）」。"
                return
            }
            guard screenSnapPipelineTask == nil, !session.isSending else {
                session.lastError = screenSnapPipelineTask != nil
                    ? "上一次截屏旁白尚未结束，请稍后再试。"
                    : "当前正在与模型通信，请稍后再试。"
                return
            }
            var merged = ruleSnapshot
            merged.lastFiredAt = settings.triggers[idx].lastFiredAt
            let task = Task { @MainActor [weak self] in
                defer { self?.screenSnapPipelineTask = nil }
                guard let self else { return }
                await self.runScreenSnapPipeline(rule: merged, forceFire: true)
            }
            screenSnapPipelineTask = task
            await task.value
            return
        }
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

    /// 菜单栏「截屏并旁白」：优先**第一条已启用**的截屏规则；若无则取第一条截屏规则（与设置页「立即触发」同为 `forceFire`，避免列表未勾选启用时菜单无反应）。
    func fireScreenSnapFromMenuBar() async {
        guard settings.screenSnapTriggerMasterEnabled else {
            session.lastError = "请先在「隐私」中打开截屏类触发总开关。"
            return
        }
        let rule = settings.triggers.first(where: { $0.enabled && $0.kind == .screenSnap })
            ?? settings.triggers.first(where: { $0.kind == .screenSnap })
        guard let rule else {
            session.lastError = "请先在「智能体设置 → 触发器」中添加一条「截屏」规则。"
            return
        }
        guard screenSnapPipelineTask == nil, !session.isSending else {
            session.lastError = screenSnapPipelineTask != nil
                ? "上一次截屏旁白尚未结束，请稍后再试。"
                : "当前正在与模型通信，请稍后再试。"
            return
        }
        let task = Task { @MainActor [weak self] in
            defer { self?.screenSnapPipelineTask = nil }
            guard let self else { return }
            await self.runScreenSnapPipeline(rule: rule, forceFire: true)
        }
        screenSnapPipelineTask = task
        await task.value
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
            let minWait: TimeInterval = rule.kind == .screenSnap
                ? rule.screenSnapEffectiveMinIntervalSeconds()
                : rule.cooldownSeconds
            if let last = rule.lastFiredAt, now.timeIntervalSince(last) < minWait {
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
            case .screenSnap:
                if evaluateScreenSnapSchedule(rule: rule, ctx: ctx) {
                    scheduleScreenSnapPipeline(ruleID: rule.id)
                }
                fired = false
            case .careInteraction:
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

    /// 自动截屏：总开关、权限、冷却+间隔、宠物可见、未在发送、无在途管线。
    private func evaluateScreenSnapSchedule(rule: AgentTriggerRule, ctx: TriggerEvalContext) -> Bool {
        guard rule.kind == .screenSnap else { return false }
        guard settings.screenSnapTriggerMasterEnabled else { return false }
        guard ScreenCaptureService.hasScreenRecordingPermission else { return false }
        guard screenSnapPipelineTask == nil, !session.isSending else { return false }
        if rule.screenSnapOnlyWhenPetVisible, !isPetVisible() { return false }
        // 降低评估频率，避免每秒打扰 SCK
        guard ctx.tickIndex % 5 == 0 else { return false }
        let matched = selectMatchedRoute(rule: rule, ctx: ctx) ?? selectMatchedRouteForForceFire(rule: rule, ctx: ctx)
        return matched != nil
    }

    private func scheduleScreenSnapPipeline(ruleID: UUID) {
        guard screenSnapPipelineTask == nil else { return }
        screenSnapPipelineTask = Task { @MainActor [weak self] in
            defer { self?.screenSnapPipelineTask = nil }
            guard let self else { return }
            guard let rule = self.settings.triggers.first(where: { $0.id == ruleID && $0.kind == .screenSnap }) else { return }
            await self.runScreenSnapPipeline(rule: rule, forceFire: false)
        }
    }

    /// 截屏成功后才写入 `lastFiredAt`（与定时等「先写再请求」不同，避免失败仍进入长冷却）。
    private func runScreenSnapPipeline(rule: AgentTriggerRule, forceFire: Bool) async {
        guard settings.screenSnapTriggerMasterEnabled else { return }
        guard ScreenCaptureService.hasScreenRecordingPermission else {
            if forceFire {
                session.lastError = ScreenCaptureServiceError.permissionDenied.localizedDescription
            }
            return
        }
        if !forceFire {
            guard rule.enabled else { return }
        }
        let ctx = buildTriggerEvalContext(now: Date())
        guard let matchedRoute = selectMatchedRoute(rule: rule, ctx: ctx)
            ?? selectMatchedRouteForForceFire(rule: rule, ctx: ctx)
        else {
            if forceFire { session.lastError = "当前规则没有可用的旁白路由。" }
            return
        }

        let maxEdge = Self.clampedScreenSnapMaxEdge(rule.screenSnapMaxEdgePixels)
        let q = Self.clampedJPEGQuality(rule.screenSnapJPEGQuality)
        let jpeg: Data
        do {
            jpeg = try await ScreenCaptureService.captureMainDisplayJPEG(maxEdge: maxEdge, jpegQuality: CGFloat(q))
        } catch {
            session.lastError = error.localizedDescription
            return
        }

        let meta = Self.buildScreenCaptureMetaLine(jpegByteCount: jpeg.count, maxEdge: maxEdge, degraded: false)
        await fireScreenSnapPrologue(
            trigger: rule,
            matchedRoute: matchedRoute,
            screenCaptureMeta: meta,
            jpegData: jpeg,
            trimKeyboardBufferIfFired: false
        )
    }

    /// 与 `ScreenCaptureService.captureMainDisplayJPEG` 的上界（2048）对齐；下界 768 避免过小图难以认字。
    private static func clampedScreenSnapMaxEdge(_ v: Int) -> Int {
        min(2048, max(768, v))
    }

    private static func clampedJPEGQuality(_ v: Double) -> Double {
        min(0.85, max(0.55, v))
    }

    private static func buildScreenCaptureMetaLine(jpegByteCount: Int, maxEdge: Int, degraded: Bool) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime, .withTimeZone, .withFractionalSeconds]
        let front = readFrontmostLocalizedName()
        return "时间=\(f.string(from: Date()))；主显示器；长边≤\(maxEdge)px；JPEG≈\(jpegByteCount)字节；前台应用=\(front)；degradedToTextOnly=\(degraded ? "true" : "false")"
    }

    private func fireScreenSnapPrologue(
        trigger: AgentTriggerRule,
        matchedRoute: TriggerPromptRoute?,
        screenCaptureMeta: String,
        jpegData: Data,
        trimKeyboardBufferIfFired: Bool
    ) async {
        session.setSending(true)
        session.lastError = nil
        let key = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider)
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
            careContext: nil,
            screenCaptureMeta: screenCaptureMeta
        )
        let personality = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPayload: String
        if personality.isEmpty {
            userPayload = userLine
        } else {
            userPayload = "\(personality)\n\n\(userLine)"
        }
        let effTemp = trigger.triggerTemperature ?? settings.triggerDefaultTemperature
        let rawMax = trigger.triggerMaxTokens ?? settings.triggerDefaultMaxTokens
        let effMax = min(max(rawMax, 32), 1024)
        let partsWithImage: [AgentAPIChatContentPart] = [.text(userPayload), .imageJPEG(jpegData)]

        func send(_ parts: [AgentAPIChatContentPart]) async throws -> String {
            try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: " ",
                userMessages: [AgentAPIChatUserMessage(parts: parts)],
                temperature: effTemp,
                maxTokens: effMax,
                extendedTimeout: parts.contains(where: {
                    if case .imageJPEG = $0 { return true }
                    return false
                })
            )
        }

        do {
            let text: String
            do {
                text = try await send(partsWithImage)
            } catch let err as AgentClientError {
                if case let .http(code, _) = err, code == 400 {
                    let meta2 = Self.buildScreenCaptureMetaLine(jpegByteCount: jpegData.count, maxEdge: Self.clampedScreenSnapMaxEdge(trigger.screenSnapMaxEdgePixels), degraded: true)
                    let userLine2 = renderUserPrompt(
                        trigger: trigger,
                        matchedRoute: matchedRoute,
                        extra: extra + " （模型拒绝图像输入，已自动改为纯文字请求；请勿假装见过截图。）",
                        keySummaryLine: keySummaryLine,
                        careContext: nil,
                        screenCaptureMeta: meta2
                    )
                    let payload2 = personality.isEmpty ? userLine2 : "\(personality)\n\n\(userLine2)"
                    text = try await send([.text(payload2)])
                } else {
                    throw err
                }
            }
            if trimKeyboardBufferIfFired, trigger.kind == .keyboardPattern {
                trimRecentKeyBufferAfterKeyboardFire(trigger: trigger, matchedRoute: matchedRoute)
            }
            settings.updateTrigger(id: trigger.id) { $0.lastFiredAt = Date() }
            if let onTriggerSpeech {
                onTriggerSpeech(TriggerSpeechPayload(text: text, triggerKind: trigger.kind, userPrompt: userPayload, requestSnapshotJPEG: jpegData))
            } else {
                session.appendAssistant(text)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
        session.setSending(false)
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
        careContext: String? = nil,
        screenCaptureMeta: String = ""
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
            .replacingOccurrences(of: "{screenCaptureMeta}", with: screenCaptureMeta)
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
        let key = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider)
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
            careContext: careContextAppendix,
            screenCaptureMeta: ""
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
                onTriggerSpeech(TriggerSpeechPayload(text: text, triggerKind: trigger.kind, userPrompt: userPayload, requestSnapshotJPEG: nil))
            } else {
                session.appendAssistant(text)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
        session.setSending(false)
    }
}
