//
// AgentTriggerEngine.swift
// 定时、随机空闲、键盘模式、前台应用等触发后调用 DeepSeek 生成一句旁白。
//

import AppKit
import Foundation

@MainActor
final class AgentTriggerEngine: ObservableObject {
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

        for i in settings.triggers.indices {
            var rule = settings.triggers[i]
            guard rule.enabled else { continue }
            if let last = rule.lastFiredAt, now.timeIntervalSince(last) < rule.cooldownSeconds {
                continue
            }
            var fired = false
            switch rule.kind {
            case .timer:
                fired = evaluateTimer(rule: &rule, now: now)
            case .randomIdle:
                fired = evaluateRandomIdle(rule: rule, idle: idle)
            case .keyboardPattern:
                fired = evaluateKeyboard(rule: rule)
            case .frontApp:
                fired = evaluateFrontApp(rule: rule, frontChanged: frontChanged, currentFront: currentFront)
            case .screenSnap, .bubbleTest:
                fired = false
            }
            if fired {
                rule.lastFiredAt = now
                settings.triggers[i] = rule
                await firePrologue(trigger: rule)
            }
        }
    }

    private func evaluateTimer(rule: inout AgentTriggerRule, now: Date) -> Bool {
        guard rule.timerIntervalMinutes > 0 else { return false }
        let interval = TimeInterval(rule.timerIntervalMinutes * 60)
        guard let last = rule.lastFiredAt else { return false }
        return now.timeIntervalSince(last) >= interval
    }

    /// 每 5 秒掷一次骰子，降低刷屏概率
    private func evaluateRandomIdle(rule: AgentTriggerRule, idle: TimeInterval) -> Bool {
        guard tickIndex % 5 == 0 else { return false }
        guard isPetVisible() else { return false }
        guard idle >= TimeInterval(rule.randomIdleSeconds) else { return false }
        return Double.random(in: 0...1) < rule.randomIdleProbability
    }

    private func evaluateKeyboard(rule: AgentTriggerRule) -> Bool {
        guard settings.keyboardTriggerMasterEnabled else { return false }
        let p = rule.keyboardPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return false }
        return recentKeyBuffer.contains(p)
    }

    private func evaluateFrontApp(rule: AgentTriggerRule, frontChanged: Bool, currentFront: String) -> Bool {
        guard frontChanged else { return false }
        let needle = rule.frontAppNameContains.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return currentFront.localizedCaseInsensitiveContains(needle)
    }

    private func firePrologue(trigger: AgentTriggerRule) async {
        session.setSending(true)
        session.lastError = nil
        let key = KeychainStore.readAPIKey()
        var extra = "（系统触发：\(trigger.kind.displayName)）"
        if settings.attachKeySummary {
            let s = deskMirror.recentKeyLabelsSummary
            if !s.isEmpty {
                extra += " 最近键入摘要：\(s.prefix(80))"
            }
        }
        let userLine = "请用一两句简体中文，像桌宠一样对用户说点什么。\(extra)"
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
