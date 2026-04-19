//
// SlackSyncController.swift
// Slack Web API 轮询：入站写入本地会话、出站 chat.postMessage；去重与指数退避。
//

import Foundation
import SwiftUI

private enum SlackPersistenceKeys {
    static let config = "DesktopPet.integration.slack.config.v1"
    static let bindings = "DesktopPet.integration.slack.bindings.v1"
    static let dedupTs = "DesktopPet.integration.slack.dedupTs.v1"
}

@MainActor
final class SlackSyncController: ObservableObject {
    @Published private(set) var integrationConfig = SlackIntegrationConfig()
    @Published private(set) var bindings: [SlackChannelBinding] = []
    @Published var statusMessage: String = "Slack 未启用。"
    @Published var lastAuthUserId: String?

    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?
    private var outboundObserver: NSObjectProtocol?
    private weak var sessionRef: AgentSessionStore?
    private weak var screenWatchTasksRef: ScreenWatchTaskStore?
    private weak var agentClientRef: AgentClient?
    private weak var agentSettingsRef: AgentSettingsStore?
    private var dedupTs: [String] = []
    private var backoffSeconds: Double = 0
    private let maxDedup = 800

    init() {
        loadPersistedState()
    }

    deinit {
        if let outboundObserver {
            NotificationCenter.default.removeObserver(outboundObserver)
        }
    }

    func updateIntegrationConfig(_ config: SlackIntegrationConfig) {
        integrationConfig = config
        persistConfig()
        statusMessage = config.enabled ? "已保存配置。" : "Slack 已关闭。"
    }

    func replaceBindings(_ new: [SlackChannelBinding]) {
        bindings = new
        persistBindings()
    }

    /// 清除「跳过历史回放」标记，下次轮询会再次只标记 ts 不入库（调试用）。
    func resetChannelInitializationMarker() {
        let sid = integrationConfig.monitoredChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else {
            statusMessage = "请先填写 Slack 频道 ID。"
            return
        }
        defaults.removeObject(forKey: "DesktopPet.integration.slack.initialized.\(sid)")
        statusMessage = "已重置该频道的初始化标记。"
    }

    /// 将当前「监控频道」绑定到当前选中的本地会话（用于首次桥接）。
    func bindMonitoredChannelToActiveSession(_ session: AgentSessionStore) {
        let sid = integrationConfig.monitoredChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else {
            statusMessage = "请先填写 Slack 频道 ID。"
            return
        }
        let localId = session.activeChannelId
        bindings.removeAll { $0.slackChannelId == sid }
        bindings.append(SlackChannelBinding(slackChannelId: sid, localChannelId: localId))
        persistBindings()
        statusMessage = "已绑定：Slack \(sid) → 本地会话。"
    }

    func start(
        session: AgentSessionStore,
        screenWatchTasks: ScreenWatchTaskStore,
        agentClient: AgentClient,
        agentSettings: AgentSettingsStore
    ) {
        sessionRef = session
        screenWatchTasksRef = screenWatchTasks
        agentClientRef = agentClient
        agentSettingsRef = agentSettings
        pollTask?.cancel()
        outboundObserver = NotificationCenter.default.addObserver(
            forName: .desktopPetConversationDidAppendMessage,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                await self.handleOutboundNotification(note)
            }
        }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let outboundObserver {
            NotificationCenter.default.removeObserver(outboundObserver)
            self.outboundObserver = nil
        }
        sessionRef = nil
        screenWatchTasksRef = nil
        agentClientRef = nil
        agentSettingsRef = nil
    }

    /// 盯屏命中等：在指定频道发帖，可选挂在 `thread_ts` 下。
    func postSlackThreadReply(channelId: String, threadTs: String?, text: String) async {
        guard integrationConfig.enabled else { return }
        guard let token = KeychainStore.readSlackBotToken(), !token.isEmpty else { return }
        do {
            _ = try await SlackWebAPI.chatPostMessage(token: token, channel: channelId, text: text, threadTs: threadTs)
        } catch {
            statusMessage = "Slack 发送失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let data = defaults.data(forKey: SlackPersistenceKeys.config),
           let c = try? JSONDecoder().decode(SlackIntegrationConfig.self, from: data) {
            integrationConfig = c
        }
        if let data = defaults.data(forKey: SlackPersistenceKeys.bindings),
           let b = try? JSONDecoder().decode([SlackChannelBinding].self, from: data) {
            bindings = b
        }
        if let data = defaults.data(forKey: SlackPersistenceKeys.dedupTs),
           let d = try? JSONDecoder().decode([String].self, from: data) {
            dedupTs = d
        }
    }

    private func persistConfig() {
        if let data = try? JSONEncoder().encode(integrationConfig) {
            defaults.set(data, forKey: SlackPersistenceKeys.config)
        }
    }

    private func persistBindings() {
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: SlackPersistenceKeys.bindings)
        }
    }

    private func persistDedup() {
        if dedupTs.count > maxDedup {
            dedupTs = Array(dedupTs.prefix(maxDedup))
        }
        if let data = try? JSONEncoder().encode(dedupTs) {
            defaults.set(data, forKey: SlackPersistenceKeys.dedupTs)
        }
    }

    private func rememberTs(_ ts: String) {
        if dedupTs.contains(ts) { return }
        dedupTs.insert(ts, at: 0)
        persistDedup()
    }

    private func hasSeenTs(_ ts: String) -> Bool {
        dedupTs.contains(ts)
    }

    // MARK: - Poll loop

    private func pollLoop() async {
        while !Task.isCancelled {
            let interval = max(3, integrationConfig.pollIntervalSeconds)
            if backoffSeconds > 0 {
                let b = backoffSeconds
                backoffSeconds = 0
                try? await Task.sleep(nanoseconds: UInt64(b * 1_000_000_000))
            } else {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            if Task.isCancelled { break }
            await pollOnce()
        }
    }

    private func pollOnce() async {
        guard integrationConfig.enabled else {
            statusMessage = "Slack 未启用。"
            return
        }
        guard let token = KeychainStore.readSlackBotToken(), !token.isEmpty else {
            statusMessage = "未配置 Slack Bot Token。"
            return
        }
        let channel = integrationConfig.monitoredChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else {
            statusMessage = "请填写 Slack 频道 ID。"
            return
        }
        guard let session = sessionRef else { return }
        guard integrationConfig.syncInbound else { return }

        do {
            if lastAuthUserId == nil {
                let uid = try await SlackWebAPI.authTest(token: token)
                lastAuthUserId = uid
            }
            let data = try await SlackWebAPI.conversationsHistory(token: token, channel: channel, limit: 30)
            try await processHistoryResponse(data: data, token: token, slackChannelId: channel, session: session)
            statusMessage = "同步正常（\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))）"
        } catch let e as SlackWebAPIError {
            switch e {
            case .rateLimited(let retryAfter):
                backoffSeconds = retryAfter ?? 10
                statusMessage = "Slack 限速，\(Int(backoffSeconds)) 秒后重试。"
            default:
                statusMessage = e.localizedDescription
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func processHistoryResponse(data: Data, token: String, slackChannelId: String, session: AgentSessionStore) async throws {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try dec.decode(SlackConversationsHistoryEnvelope.self, from: data)
        guard envelope.ok else {
            throw SlackWebAPIError.apiError(envelope.error ?? "unknown")
        }
        let messages = (envelope.messages ?? []).sorted { (Double($0.ts ?? "0") ?? 0) < (Double($1.ts ?? "0") ?? 0) }

        /// 首次连接某频道时只标记已见 ts，避免把整段历史灌进本地会话。
        let initKey = "DesktopPet.integration.slack.initialized.\(slackChannelId)"
        if !defaults.bool(forKey: initKey) {
            for m in messages {
                if let ts = m.ts { rememberTs(ts) }
            }
            defaults.set(true, forKey: initKey)
            statusMessage = "已跳过该 Slack 频道历史回放，仅同步之后的新消息。"
            return
        }
        for m in messages {
            guard let ts = m.ts else { continue }
            if hasSeenTs(ts) { continue }
            if m.botId != nil { rememberTs(ts); continue }
            if let u = m.user, u == lastAuthUserId { rememberTs(ts); continue }
            guard let text = m.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                rememberTs(ts)
                continue
            }
            let stripped = Self.stripSlackMentions(text)
            await handleInboundSlackText(
                raw: stripped,
                slackTs: ts,
                slackChannelId: slackChannelId,
                session: session
            )
            rememberTs(ts)
        }
    }

    /// 去掉 `<@U123>` 等，避免命令匹配失败。
    private static func stripSlackMentions(_ s: String) -> String {
        let pattern = "<@[^>]+>"
        return s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleInboundSlackText(
        raw: String,
        slackTs: String,
        slackChannelId: String,
        session: AgentSessionStore
    ) async {
        let lower = raw.lowercased()
        if lower.hasPrefix("!pet new") {
            let rest = raw.dropFirst("!pet new".count).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rest.isEmpty ? "Slack 会话" : String(rest)
            let newId = session.createNewEmptyChannel(title: title)
            bindings.removeAll { $0.slackChannelId == slackChannelId }
            bindings.append(SlackChannelBinding(slackChannelId: slackChannelId, localChannelId: newId))
            persistBindings()
            session.appendSystemNotice("（Slack）已通过命令创建会话并绑定本频道。")
            statusMessage = "已从 Slack 创建会话「\(title)」。"
            return
        }

        if await handlePetWatchSlackMessage(raw: raw, slackTs: slackTs, slackChannelId: slackChannelId, session: session) {
            return
        }

        guard let binding = bindings.first(where: { $0.slackChannelId == slackChannelId }) else {
            statusMessage = "收到 Slack 消息但未绑定本地频道，请在「集成」中绑定或使用 `!pet new 标题`。"
            return
        }
        session.appendSlackInboundUser(channelId: binding.localChannelId, text: raw, slackTs: slackTs, slackChannelId: slackChannelId)
    }

    /// Slack 盯屏：`!pet watch` / `!pet 盯屏` 或自然语言；仅 OCR + 可选模型兜底（无亮度启发式）。无需已绑定本地会话也会在原帖下回复确认。
    private func handlePetWatchSlackMessage(
        raw: String,
        slackTs: String,
        slackChannelId: String,
        session: AgentSessionStore
    ) async -> Bool {
        guard integrationConfig.enabled, integrationConfig.syncInbound else { return false }
        guard let tasks = screenWatchTasksRef else { return false }

        let draft: SlackPetWatchDraft?
        if let q = SlackPetWatchCommand.parseQuickCommand(raw) {
            draft = q
        } else if SlackPetWatchCommand.shouldAttemptNaturalLanguageParse(raw) {
            draft = await resolveWatchDraftWithModel(userRaw: raw)
        } else {
            draft = nil
        }
        guard let d = draft else { return false }

        let ocr = d.ocrSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
        let vision = d.visionUserHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ocr.isEmpty || !vision.isEmpty else { return false }

        var conditions: [ScreenWatchCondition] = []
        if !ocr.isEmpty {
            conditions.append(.ocrContains(text: ocr, caseInsensitive: true))
        }
        let useVision = !vision.isEmpty

        let finalTitle: String = {
            let t = d.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            if !ocr.isEmpty, vision.isEmpty { return "Slack盯屏：\(ocr)" }
            if ocr.isEmpty, !vision.isEmpty { return "Slack盯屏（模型）" }
            return "Slack盯屏"
        }()

        let task = ScreenWatchTask(
            title: finalTitle,
            isEnabled: true,
            sampleIntervalSeconds: 3,
            conditions: conditions,
            useVisionFallback: useVision,
            visionUserHint: vision,
            visionFallbackCooldownSeconds: 30,
            repeatAfterHit: false,
            repeatCooldownSeconds: 60,
            creationSource: .slackAutomated,
            slackReportChannelId: slackChannelId,
            slackReportThreadTs: slackTs
        )
        tasks.upsert(task)

        var ack = "🐱 已为你创建盯屏任务「\(finalTitle)」（猫猫自动）。"
        if !ocr.isEmpty { ack += "\n· OCR 包含：\(ocr)" }
        if useVision { ack += "\n· 已开模型兜底（截图 YES/NO）。" } else { ack += "\n· 未开模型兜底（仅 OCR）。" }
        ack += "\n命中后我会在此线程回复你。"
        await postSlackThreadReply(channelId: slackChannelId, threadTs: slackTs, text: ack)

        if let binding = bindings.first(where: { $0.slackChannelId == slackChannelId }) {
            session.appendSystemNoticeInChannel(
                channelId: binding.localChannelId,
                text: "（Slack）猫猫已创建盯屏任务「\(finalTitle)」，仅 OCR\(useVision ? "+模型兜底" : "")。"
            )
        }
        statusMessage = "已从 Slack 创建盯屏任务「\(finalTitle)」。"
        return true
    }

    private func resolveWatchDraftWithModel(userRaw: String) async -> SlackPetWatchDraft? {
        guard let client = agentClientRef, let settings = agentSettingsRef else { return nil }
        let key = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider)
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sys = """
        你是解析器。用户通过 Slack 让桌宠「盯屏」：根据 Mac 主屏截图判断是否出现某文字（OCR），和/或用多模态模型根据截图判断是否满足某描述。
        只输出一个 JSON 对象，不要 markdown，不要解释。字段：
        - create (bool): 用户是否在请求盯屏、看着/盯着屏幕、留意界面变化、进度是否完成、是否出现某字样等。
        - taskTitle (string): 短标题（中文优先，≤40字）。
        - ocrSubstring (string): 若用户关心屏幕上是否出现某固定文字，填子串；否则空串。
        - visionUserHint (string): 若需要看图才能判断（如训练是否完成、界面是否处于某状态），写成给多模态模型的简短判断说明（中文）；否则空串。
        重要：用户说「进度条满了/走完/到 100%/加载完成」等依赖条形区域视觉、又无稳定可 OCR 的固定短语文案时，必须把判定要求写进 visionUserHint（例如「主屏当前焦点窗口里，主要进度条是否已明显填满或接近完成」），不要留空；ocrSubstring 可留空。
        当 create 为 true 时，ocrSubstring 与 visionUserHint 至少一项非空；否则 create 为 false。
        """
        do {
            let reply = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: sys,
                messages: [["role": "user", "content": userRaw]],
                temperature: 0.1,
                maxTokens: 400
            )
            return SlackPetWatchCommand.draftFromModelJSON(reply)
        } catch {
            return nil
        }
    }

    // MARK: - Outbound

    private func handleOutboundNotification(_ note: Notification) async {
        guard integrationConfig.enabled, integrationConfig.syncOutbound else { return }
        guard let token = KeychainStore.readSlackBotToken(), !token.isEmpty else { return }
        guard
            let chStr = note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendChannelId] as? String,
            let localChannelId = UUID(uuidString: chStr),
            let role = note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendRole] as? String,
            role == "user" || role == "assistant",
            let origin = note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendOrigin] as? String,
            origin == "local",
            let text = note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendContent] as? String
        else { return }

        guard let binding = bindings.first(where: { $0.localChannelId == localChannelId }) else { return }
        let prefix = role == "user" ? "🐱 用户" : "🐱 猫猫"
        let outbound = "\(prefix)：\(text)"
        do {
            let data = try await SlackWebAPI.chatPostMessage(token: token, channel: binding.slackChannelId, text: outbound, threadTs: nil)
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            let env = try dec.decode(SlackChatPostEnvelope.self, from: data)
            if let ts = env.ts {
                rememberTs(ts)
            }
        } catch {
            statusMessage = "Slack 发送失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Slack Web API

private enum SlackWebAPIError: LocalizedError {
    case apiError(String)
    case rateLimited(retryAfter: Double?)

    var errorDescription: String? {
        switch self {
        case .apiError(let s): return "Slack API：\(s)"
        case .rateLimited(let r):
            if let r { return "Slack 限速，请 \(Int(r)) 秒后再试。" }
            return "Slack 限速。"
        }
    }
}

private struct SlackConversationsHistoryEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let messages: [SlackHistoryMessage]?
}

private struct SlackHistoryMessage: Decodable {
    let type: String?
    let subtype: String?
    let user: String?
    let text: String?
    let ts: String?
    let botId: String?
}

private struct SlackAuthTestEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let userId: String?
}

private struct SlackChatPostEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let ts: String?
}

private enum SlackWebAPI {
    static func authTest(token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://slack.com/api/auth.test")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(SlackAuthTestEnvelope.self, from: data)
        guard env.ok, let uid = env.userId else {
            throw SlackWebAPIError.apiError(env.error ?? "auth.test failed")
        }
        return uid
    }

    static func conversationsHistory(token: String, channel: String, limit: Int) async throws -> Data {
        var c = URLComponents(string: "https://slack.com/api/conversations.history")!
        c.queryItems = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        return data
    }

    static func chatPostMessage(token: String, channel: String, text: String, threadTs: String? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["channel": channel, "text": text]
        if let ts = threadTs?.trimmingCharacters(in: .whitespacesAndNewlines), !ts.isEmpty {
            body["thread_ts"] = ts
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(SlackChatPostEnvelope.self, from: data)
        guard env.ok else {
            throw SlackWebAPIError.apiError(env.error ?? "chat.postMessage failed")
        }
        return data
    }
}
