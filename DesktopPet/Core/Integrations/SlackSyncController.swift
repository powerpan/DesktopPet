//
// SlackSyncController.swift
// Slack Web API 轮询：入站写入本地会话、出站 chat.postMessage；去重与指数退避。
//

import AppKit
import CoreGraphics
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
    private weak var multimodalLimitsRef: MultimodalAttachmentLimitsStore?
    private weak var accessibilityPermissionRef: AccessibilityPermissionManager?
    private let remoteClickSessions = SlackRemoteClickSessionStore()
    private var dedupTs: [String] = []
    private var backoffSeconds: Double = 0
    private let maxDedup = 800

    init() {
        loadPersistedState()
        #if DEBUG
        SlackPetRemoteClickCommand.runSanityChecks()
        #endif
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
        agentSettings: AgentSettingsStore,
        multimodalLimits: MultimodalAttachmentLimitsStore,
        accessibilityPermission: AccessibilityPermissionManager
    ) {
        sessionRef = session
        screenWatchTasksRef = screenWatchTasks
        agentClientRef = agentClient
        agentSettingsRef = agentSettings
        multimodalLimitsRef = multimodalLimits
        accessibilityPermissionRef = accessibilityPermission
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
        multimodalLimitsRef = nil
        accessibilityPermissionRef = nil
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

    /// 条件触发旁白：发到「连接」里配置的 Slack 监控频道（顶层消息，非线程）。
    func postTriggerNarrativeToSlack(triggerKind: AgentTriggerKind, text: String) async {
        guard integrationConfig.enabled else { return }
        guard let token = KeychainStore.readSlackBotToken(), !token.isEmpty else {
            statusMessage = "Slack 未配置 Bot Token，无法推送触发旁白。"
            return
        }
        let ch = integrationConfig.monitoredChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ch.isEmpty else {
            statusMessage = "请在「连接」填写 Slack 监控频道 ID，才能推送触发旁白。"
            return
        }
        let body = "🐱 **触发旁白**（\(triggerKind.displayName)）\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        do {
            _ = try await SlackWebAPI.chatPostMessage(token: token, channel: ch, text: body, threadTs: nil)
        } catch {
            statusMessage = "Slack 触发旁白发送失败：\(error.localizedDescription)"
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
            await pollRemoteClickThreadReplies(token: token, slackChannelId: channel, session: session)
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
            let trimmedText = m.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let files = m.files ?? []
            if trimmedText.isEmpty && files.isEmpty {
                rememberTs(ts)
                continue
            }
            let stripped = Self.stripSlackMentions(trimmedText)
            await handleInboundSlackText(
                raw: stripped,
                slackTs: ts,
                slackThreadParentTs: m.threadTs,
                slackChannelId: slackChannelId,
                token: token,
                files: files,
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
        slackThreadParentTs: String?,
        slackChannelId: String,
        token: String,
        files: [SlackHistoryFile],
        session: AgentSessionStore
    ) async {
        if await tryHandleRemoteClickCoordinateIfNeeded(
            raw: raw,
            slackTs: slackTs,
            slackThreadParentTs: slackThreadParentTs,
            slackChannelId: slackChannelId,
            token: token,
            session: session
        ) {
            return
        }

        if !raw.isEmpty, let parsed = SlackPetScreenSnapSettingsCommand.parse(raw), let agent = agentSettingsRef {
            let parent = slackThreadParentTs?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let threadTs = parent.isEmpty ? slackTs : parent
            await applySlackPetScreenSnapSettingsCommand(
                parsed,
                agent: agent,
                channelId: slackChannelId,
                threadTs: threadTs
            )
            statusMessage = "已处理 Slack 截屏档位指令。"
            return
        }

        if !raw.isEmpty, SlackPetHelpCommand.isHelpRequest(raw) {
            let parent = slackThreadParentTs?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let threadTs = parent.isEmpty ? slackTs : parent
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: threadTs,
                text: SlackPetHelpCommand.integrationHelpMarkdown()
            )
            statusMessage = "已在 Slack 回复帮助说明。"
            return
        }

        let uploads: [(filename: String, mimeType: String, data: Data)]
        let rejections: [String]
        if files.isEmpty {
            uploads = []
            rejections = []
        } else {
            let r = await ingestSlackFilesFromSlackAPI(files: files, token: token)
            uploads = r.uploads
            rejections = r.rejections
        }

        if !raw.isEmpty {
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
        }

        if !raw.isEmpty, SlackPetRemoteClickCommand.isStartCommand(raw) {
            await handleRemoteClickStart(
                raw: raw,
                slackTs: slackTs,
                slackThreadParentTs: slackThreadParentTs,
                slackChannelId: slackChannelId,
                token: token,
                session: session
            )
            return
        }

        if !raw.isEmpty {
            if await handlePetWatchSlackMessage(raw: raw, slackTs: slackTs, slackChannelId: slackChannelId, session: session) {
                return
            }
        }

        if !rejections.isEmpty {
            let body =
                "🐱 以下附件无法传给模型（超过你在「集成」中配置的大小，或格式不支持）：\n"
                + rejections.joined(separator: "\n")
            await postSlackThreadReply(channelId: slackChannelId, threadTs: slackTs, text: body)
        }

        guard let binding = bindings.first(where: { $0.slackChannelId == slackChannelId }) else {
            statusMessage = "收到 Slack 消息但未绑定本地频道，请在「连接」中绑定或使用 `!pet new 标题`。"
            return
        }

        guard !raw.isEmpty || !uploads.isEmpty else { return }
        session.appendSlackInboundUser(
            channelId: binding.localChannelId,
            text: raw,
            slackTs: slackTs,
            slackChannelId: slackChannelId,
            uploads: uploads
        )
    }

    /// 下载 Slack `files` 并校验多模态限额；失败项写入 `rejections` 供在 Slack 线程回复用户。
    private func ingestSlackFilesFromSlackAPI(
        files: [SlackHistoryFile],
        token: String
    ) async -> (uploads: [(filename: String, mimeType: String, data: Data)], rejections: [String]) {
        guard let limits = multimodalLimitsRef else {
            return ([], ["（应用未注入多模态限额，已跳过 Slack 附件）"])
        }
        var uploads: [(filename: String, mimeType: String, data: Data)] = []
        var rejections: [String] = []
        for f in files {
            let name = (f.name ?? "未命名").trimmingCharacters(in: .whitespacesAndNewlines)
            let urlStr = [f.urlPrivateDownload, f.urlPrivate].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
            guard !urlStr.isEmpty else {
                rejections.append("「\(name)」缺少可下载地址（请为 Bot 授予 **files:read**，并确保文件未过期）。")
                continue
            }
            let data: Data
            do {
                data = try await SlackWebAPI.downloadPrivateFile(token: token, urlString: urlStr)
            } catch {
                rejections.append("「\(name)」下载失败：\(error.localizedDescription)")
                continue
            }
            let sniffed = ChatMultimodalAttachmentCodec.declaredMime(filename: name, data: data)
            let mimeHint = (f.mimetype?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? sniffed
            let isImg = mimeHint.hasPrefix("image/") || sniffed.hasPrefix("image/")
            let cap = isImg ? limits.maxImageAttachmentBytes : limits.maxFileAttachmentBytes
            if data.count > cap {
                rejections.append(
                    "「\(name)」约 \(data.count / 1024) KB，超过\(isImg ? "单张图片" : "单个文件")上限 \(cap / 1024) KB。"
                )
                continue
            }
            do {
                _ = try ChatMultimodalAttachmentCodec.partsFromLocalUpload(data: data, filename: name, limits: limits)
                let mime = ChatMultimodalAttachmentCodec.declaredMime(filename: name, data: data)
                uploads.append((name, mime, data))
            } catch {
                rejections.append("「\(name)」：\(error.localizedDescription)")
            }
        }
        return (uploads, rejections)
    }

    // MARK: - Slack 截屏档位

    private func applySlackPetScreenSnapSettingsCommand(
        _ parsed: SlackPetScreenSnapSettingsCommand.Result,
        agent: AgentSettingsStore,
        channelId: String,
        threadTs: String
    ) async {
        switch parsed {
        case .remotePickOnly(let pick):
            agent.screenSnapSlackRemoteDisplayPick = pick
            let label = pick.zhShortLabel
            let tail: String
            if agent.screenSnapCaptureTarget == .off {
                tail =
                    "当前 Mac 上「截屏类触发」仍为**关**，**不能**通过 Slack 远程改为「开」；自动截屏与菜单栏截屏旁白不会执行。\n\n已记录：远程点屏等会优先按 **\(label)** 截取（需屏幕录制权限）。若要启用自动截屏，请在装有 DesktopPet 的 Mac 上打开：**智能体工作台 → 自动化 → 隐私**，选择「截取主屏」「截取副屏」或「截取焦点屏」。"
            } else {
                tail =
                    "当前本机已选择「\(agent.screenSnapCaptureTarget.privacyMenuTitle)」；自动截屏按该档位执行。本偏好仍会在你将来改回「关」时，供远程点屏等使用。"
            }
            await postSlackThreadReply(
                channelId: channelId,
                threadTs: threadTs,
                text: "🐱 已通过 Slack 记录远程截屏目标为 **\(label)**。\n\n\(tail)"
            )
        case .setCaptureTarget(let t):
            if t != .off, agent.screenSnapCaptureTarget == .off {
                await postSlackThreadReply(
                    channelId: channelId,
                    threadTs: threadTs,
                    text:
                        """
                        🐱 当前 Mac 上「截屏类触发」为**关**，**不能通过 Slack 远程改为「截取主屏 / 截取副屏 / 截取焦点屏」**（避免在你不知情时打开截屏与多模态上传）。

                        请在本机 **智能体工作台 → 自动化 → 隐私** 中手动选择「截取主屏」「截取副屏」或「截取焦点屏」。

                        你仍可在总开关为关时，用 Slack **仅选择显示器**：`!pet screen pick main` / `pick secondary` / `pick focus`，或发「**截屏目标主屏**」「**截屏目标副屏**」「**截屏目标焦点屏**」，供远程点屏等按该屏截取。
                        """
                )
                return
            }
            agent.screenSnapCaptureTarget = t
            let label = t.privacyMenuTitle
            await postSlackThreadReply(
                channelId: channelId,
                threadTs: threadTs,
                text: "🐱 已把截屏类触发设为：**\(label)**（本机已落盘）。"
            )
        }
    }

    // MARK: - Slack 远程点屏

    private func pollRemoteClickThreadReplies(token: String, slackChannelId: String, session: AgentSessionStore) async {
        let pending = remoteClickSessions.allAwaitingKeys().filter { $0.channelId == slackChannelId }
        for item in pending {
            let data: Data
            do {
                data = try await SlackWebAPI.conversationsReplies(
                    token: token,
                    channel: slackChannelId,
                    ts: item.threadRootTs,
                    limit: 50
                )
            } catch {
                continue
            }
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            guard let env = try? dec.decode(SlackConversationsRepliesEnvelope.self, from: data), env.ok else { continue }
            let messages = (env.messages ?? []).sorted { (Double($0.ts ?? "0") ?? 0) < (Double($1.ts ?? "0") ?? 0) }
            for m in messages {
                guard let ts = m.ts else { continue }
                if hasSeenTs(ts) { continue }
                if m.botId != nil { rememberTs(ts); continue }
                if let u = m.user, u == lastAuthUserId { rememberTs(ts); continue }
                let trimmedText = m.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let files = m.files ?? []
                if trimmedText.isEmpty && files.isEmpty {
                    rememberTs(ts)
                    continue
                }
                let stripped = Self.stripSlackMentions(trimmedText)
                await handleInboundSlackText(
                    raw: stripped,
                    slackTs: ts,
                    slackThreadParentTs: m.threadTs ?? item.threadRootTs,
                    slackChannelId: slackChannelId,
                    token: token,
                    files: files,
                    session: session
                )
                rememberTs(ts)
            }
        }
    }

    private func isPlausibleCoordinateAttempt(_ raw: String) -> Bool {
        let s = raw.lowercased()
        if s.contains("="), (s.contains("x") || s.contains("y")) { return true }
        let parts = raw.split { ch in ",;，、 \t".contains(ch) }.map(String.init).filter { !$0.isEmpty }
        return parts.count >= 2 && parts.contains(where: { $0.rangeOfCharacter(from: .decimalDigits) != nil })
    }

    /// 使用当前会话中的显示器几何与上一张标尺图尺寸执行点击，并回到「是否继续」。
    private func performSlackRemoteClickFromNorm(
        pair: (Double, Double),
        sess: SlackRemoteClickSessionStore.Session,
        slackChannelId: String,
        parentThreadTs: String,
        session: AgentSessionStore
    ) async {
        accessibilityPermissionRef?.refreshStatus(prompt: false, bumpUI: false)
        let ax = accessibilityPermissionRef?.isGranted ?? false
        do {
            let pt = try RemoteClickExecutor.quartzPoint(
                normX: pair.0,
                normY: pair.1,
                displayBounds: sess.displayBounds,
                imagePixelSize: sess.imagePixelSize
            )
            try RemoteClickExecutor.performLeftClick(at: pt, accessibilityTrusted: ax)
            remoteClickSessions.setAwaitingContinue(channelId: slackChannelId, threadRootTs: parentThreadTs)
            let lab = sess.displayShortLabelZh
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: parentThreadTs,
                text:
                    "🐱 已在**\(lab)**执行一次左键点击（\(String(format: "%.0f", pair.0 * 100)),\(String(format: "%.0f", pair.1 * 100)) 标尺坐标）。\n\n若要**再来一轮**（重新截屏并点下一处），请回复 **继续** 或 **再来一次**；也可 **`继续`+坐标**（如 `继续90，62`）沿用当前坐标图直接再点。结束请回复 **结束** 或 **停止**。"
            )
            if let binding = bindings.first(where: { $0.slackChannelId == slackChannelId }) {
                session.appendSystemNoticeInChannel(
                    channelId: binding.localChannelId,
                    text: "（Slack）远程点屏已在\(lab)执行一次点击；可在 Slack 线程回复「继续」多轮操作。"
                )
            }
            statusMessage = "Slack 远程点屏已执行。"
        } catch let e as RemoteClickExecutorError {
            await postSlackThreadReply(channelId: slackChannelId, threadTs: parentThreadTs, text: "🐱 \(e.localizedDescription)")
        } catch {
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: parentThreadTs,
                text: "🐱 点击失败：\(error.localizedDescription)"
            )
        }
    }

    private func tryHandleRemoteClickCoordinateIfNeeded(
        raw: String,
        slackTs: String,
        slackThreadParentTs: String?,
        slackChannelId: String,
        token: String,
        session: AgentSessionStore
    ) async -> Bool {
        guard let parent = slackThreadParentTs?.trimmingCharacters(in: .whitespacesAndNewlines), !parent.isEmpty else {
            return false
        }
        guard let sess = remoteClickSessions.session(channelId: slackChannelId, threadRootTs: parent) else {
            return false
        }

        switch sess.status {
        case .awaitingContinue:
            if SlackPetRemoteClickCommand.isEndRemoteClickReply(raw) {
                remoteClickSessions.complete(channelId: slackChannelId, threadRootTs: parent)
                await postSlackThreadReply(
                    channelId: slackChannelId,
                    threadTs: parent,
                    text: "🐱 已结束远程点屏会话。"
                )
                statusMessage = "Slack 远程点屏已结束。"
                return true
            }

            switch SlackPetRemoteClickCommand.parseContinueAfterClickMessage(raw) {
            case .combinedCoordinateTail(let tail):
                if let pair = SlackPetRemoteClickCommand.parseCoordinateReply(tail) {
                    await performSlackRemoteClickFromNorm(
                        pair: pair,
                        sess: sess,
                        slackChannelId: slackChannelId,
                        parentThreadTs: parent,
                        session: session
                    )
                } else {
                    await postSlackThreadReply(
                        channelId: slackChannelId,
                        threadTs: parent,
                        text: "🐱 无法在「继续」后解析坐标。请用如 **`继续90，62`**、**`继续 50, 50`**、**`再来一次 x=0.5 y=0.5`**，或先发 **继续** 再单独发坐标。"
                    )
                }
                return true
            case .bareContinue:
                await handleRemoteClickContinueRound(
                    channelId: slackChannelId,
                    threadRootTs: parent,
                    token: token,
                    session: session
                )
                return true
            case .notContinueLeadIn:
                break
            }

            if SlackPetRemoteClickCommand.isContinueRemoteClickReply(raw) {
                await handleRemoteClickContinueRound(
                    channelId: slackChannelId,
                    threadRootTs: parent,
                    token: token,
                    session: session
                )
                return true
            }
            if SlackPetRemoteClickCommand.parseCoordinateReply(raw) != nil || isPlausibleCoordinateAttempt(raw) {
                await postSlackThreadReply(
                    channelId: slackChannelId,
                    threadTs: parent,
                    text: "🐱 当前在等待是否继续：请先回复 **继续**（或 **`继续`+坐标** 沿用当前坐标图），或 **再来一次** 截新图，或回复 **结束** 退出。"
                )
                return true
            }
            return false

        case .awaitingCoordinate:
            if let pair = SlackPetRemoteClickCommand.parseCoordinateReply(raw) {
                await performSlackRemoteClickFromNorm(
                    pair: pair,
                    sess: sess,
                    slackChannelId: slackChannelId,
                    parentThreadTs: parent,
                    session: session
                )
                return true
            }

            if isPlausibleCoordinateAttempt(raw) {
                await postSlackThreadReply(
                    channelId: slackChannelId,
                    threadTs: parent,
                    text: "🐱 坐标无法解析或超出 0–100（或 0–1）范围。请重试，例如 `50,50` 或 `x=0.5 y=0.5`。"
                )
                return true
            }

            return false
        }
    }

    /// 用户回复「继续」：再次截屏、上传标尺图，并回到等待坐标。
    private func handleRemoteClickContinueRound(
        channelId: String,
        threadRootTs: String,
        token: String,
        session: AgentSessionStore
    ) async {
        let postThreadTs = threadRootTs

        guard ScreenCaptureService.hasScreenRecordingPermission else {
            await postSlackThreadReply(
                channelId: channelId,
                threadTs: postThreadTs,
                text: "🐱 需要「屏幕录制」权限才能继续截屏。请授权后回复 **继续**。"
            )
            return
        }

        guard let agent = agentSettingsRef else { return }
        let imgTarget = agent.effectiveCaptureTargetForRemoteClickImaging()
        let displayBounds: CGRect
        let overlay: Data
        do {
            displayBounds = try await ScreenCaptureService.displayBounds(for: imgTarget)
            let jpeg = try await ScreenCaptureService.captureJPEG(for: imgTarget, maxEdge: 1600, jpegQuality: 0.82)
            overlay = RemoteClickOverlayRenderer.renderOverlayOnJPEG(jpeg)
        } catch let e as ScreenCaptureServiceError where e == .noSecondaryDisplay {
            await postSlackThreadReply(
                channelId: channelId,
                threadTs: postThreadTs,
                text: "🐱 未检测到可用副显示器，无法按当前偏好截副屏。请改用 `!pet screen pick main` / 「截屏目标主屏」，或在本机接上副屏后再试。"
            )
            return
        } catch {
            await postSlackThreadReply(
                channelId: channelId,
                threadTs: postThreadTs,
                text: "🐱 截屏失败，无法继续：\(error.localizedDescription)"
            )
            return
        }

        let px = Self.jpegPixelSize(ofJPEG: overlay) ?? CGSize(width: 1280, height: 720)
        remoteClickSessions.resumeAwaitingCoordinate(
            channelId: channelId,
            threadRootTs: threadRootTs,
            displayBounds: displayBounds,
            imagePixelSize: px,
            displayShortLabelZh: imgTarget.shortZhLabel
        )

        let intro =
            "🐱 新一张\(imgTarget.shortZhLabel)坐标图（0–100 标尺）。请在本线程回复坐标；点击完成后仍可回复 **继续** 多轮，或 **结束** 退出。"

        do {
            _ = try await SlackWebAPI.filesUpload(
                token: token,
                channel: channelId,
                threadTs: postThreadTs,
                filename: "remote_click_overlay.jpg",
                mimeType: "image/jpeg",
                initialComment: intro,
                fileData: overlay
            )
        } catch {
            await postSlackThreadReply(
                channelId: channelId,
                threadTs: postThreadTs,
                text:
                    "\(intro)\n\n（上传失败：\(error.localizedDescription)。仍可凭记忆输入坐标；建议修好 **files:write** 与外部上传。）"
            )
        }

        if let binding = bindings.first(where: { $0.slackChannelId == channelId }) {
            session.appendSystemNoticeInChannel(
                channelId: binding.localChannelId,
                text: "（Slack）远程点屏已继续下一轮，请在 Slack 线程回复坐标。"
            )
        }
        statusMessage = "Slack 远程点屏已继续下一轮。"
    }

    private func handleRemoteClickStart(
        raw: String,
        slackTs: String,
        slackThreadParentTs: String?,
        slackChannelId: String,
        token: String,
        session: AgentSessionStore
    ) async {
        _ = raw
        let trimmedParent = slackThreadParentTs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadRoot: String = {
            if let t = trimmedParent, !t.isEmpty { return t }
            return slackTs
        }()
        let postThreadTs = threadRoot

        guard ScreenCaptureService.hasScreenRecordingPermission else {
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: postThreadTs,
                text: "🐱 远程点屏需要「屏幕录制」权限。请在系统设置 → 隐私与安全性 → 屏幕录制 中允许本应用，然后重试 `!pet click` / `!pet 点屏` 或中文触发词（如「远程点屏」）。"
            )
            return
        }

        guard let agent = agentSettingsRef else { return }
        let imgTarget = agent.effectiveCaptureTargetForRemoteClickImaging()
        let displayBounds: CGRect
        let jpeg: Data
        do {
            displayBounds = try await ScreenCaptureService.displayBounds(for: imgTarget)
            jpeg = try await ScreenCaptureService.captureJPEG(for: imgTarget, maxEdge: 1600, jpegQuality: 0.82)
        } catch let e as ScreenCaptureServiceError where e == .noSecondaryDisplay {
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: postThreadTs,
                text: "🐱 未检测到可用副显示器，无法按当前偏好截副屏。请发 `!pet screen pick main` / 「截屏目标主屏」，或在本机接上副屏后再发起远程点屏。"
            )
            return
        } catch {
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: postThreadTs,
                text: "🐱 截屏失败：\(error.localizedDescription)"
            )
            return
        }

        let overlay = RemoteClickOverlayRenderer.renderOverlayOnJPEG(jpeg)
        let px = Self.jpegPixelSize(ofJPEG: overlay) ?? CGSize(width: 1280, height: 720)

        remoteClickSessions.beginSession(
            channelId: slackChannelId,
            threadRootTs: threadRoot,
            displayBounds: displayBounds,
            imagePixelSize: px,
            overlayJPEG: nil,
            displayShortLabelZh: imgTarget.shortZhLabel
        )

        let intro =
            "🐱 \(imgTarget.shortZhLabel)坐标图（0–100 标尺，用户视角左下为原点）。请在本线程回复坐标，例如 `50,50` 或 `x=0.5 y=0.5`（支持 0–100 或 0–1）。每轮点击后会询问是否继续；回复 **继续** / **再来一次** 可重新截屏再点，回复 **结束** 退出。约 5 分钟无操作超时。"

        do {
            _ = try await SlackWebAPI.filesUpload(
                token: token,
                channel: slackChannelId,
                threadTs: postThreadTs,
                filename: "remote_click_overlay.jpg",
                mimeType: "image/jpeg",
                initialComment: intro,
                fileData: overlay
            )
        } catch {
            await postSlackThreadReply(
                channelId: slackChannelId,
                threadTs: postThreadTs,
                text:
                    "\(intro)\n\n（上传坐标图失败：\(error.localizedDescription)。请确认 Bot 拥有 **files:write**，且工作区允许外部上传（`files.getUploadURLExternal` / `files.completeUploadExternal`）；你仍可凭记忆输入坐标，但强烈建议修好上传以免对错屏。）"
            )
        }

        if let binding = bindings.first(where: { $0.slackChannelId == slackChannelId }) {
            session.appendSystemNoticeInChannel(
                channelId: binding.localChannelId,
                text: "（Slack）已发起远程点屏，请在 Slack 该线程回复坐标。"
            )
        }
        statusMessage = "Slack 远程点屏已发送坐标图。"
    }

    private static func jpegPixelSize(ofJPEG data: Data) -> CGSize? {
        guard let img = NSImage(data: data),
              let rep = img.representations.first as? NSBitmapImageRep,
              rep.pixelsWide > 0,
              rep.pixelsHigh > 0 else { return nil }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
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
        var outbound = "\(prefix)：\(text)"
        if let n = note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendAttachmentCount] as? Int, n > 0 {
            outbound += "（另含 \(n) 个附件；Slack 出站仅同步文字）"
        }
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

private struct SlackConversationsRepliesEnvelope: Decodable {
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
    let threadTs: String?
    let botId: String?
    let files: [SlackHistoryFile]?
}

private struct SlackHistoryFile: Decodable {
    let id: String?
    let name: String?
    let mimetype: String?
    let size: Int?
    let urlPrivate: String?
    let urlPrivateDownload: String?
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

    static func downloadPrivateFile(token: String, urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw SlackWebAPIError.apiError("无效的文件 URL")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw SlackWebAPIError.apiError("文件下载无 HTTP 响应")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw SlackWebAPIError.apiError("文件下载 HTTP \(http.statusCode)：\(s.prefix(160))")
        }
        return data
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
        // 使用 `markdown_text`：Slack 标准 Markdown（`**粗体**` 等），与客户端「Markdown」一致。
        // 勿与顶层 `text` 同发（会 `markdown_text_conflict`）；顶层 `text`+mrkdwn 的 `*粗体*` 在部分客户端会整段当纯文本，星号原样显示。
        let maxMarkdown = 12_000
        let markdownBody: String = {
            guard text.count > maxMarkdown else { return text }
            let head = String(text.prefix(max(0, maxMarkdown - 24)))
            return head + "\n\n…（消息过长已截断）"
        }()
        var body: [String: Any] = [
            "channel": channel,
            "markdown_text": markdownBody,
        ]
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

    static func conversationsReplies(token: String, channel: String, ts: String, limit: Int) async throws -> Data {
        var c = URLComponents(string: "https://slack.com/api/conversations.replies")!
        c.queryItems = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "ts", value: ts),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard let url = c.url else {
            throw SlackWebAPIError.apiError("无效 conversations.replies URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        return data
    }

    /// 使用 Slack 推荐的外部上传链路（`files.getUploadURLExternal` → POST 字节 → `files.completeUploadExternal`），替代已弃用的 `files.upload`。
    static func filesUpload(
        token: String,
        channel: String,
        threadTs: String?,
        filename: String,
        mimeType: String,
        initialComment: String?,
        fileData: Data
    ) async throws -> Data {
        guard !fileData.isEmpty else {
            throw SlackWebAPIError.apiError("文件为空，无法上传")
        }

        // 1) 申请边缘上传 URL（官方 curl 为表单字段；用带 host 的 URLComponents 生成 x-www-form-urlencoded 体，避免空 URL 时 percentEncodedQuery 为 nil）
        var getComp = URLComponents(string: "https://slack.com/api/files.getUploadURLExternal")!
        getComp.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "length", value: String(fileData.count)),
        ]
        guard let getQuery = getComp.percentEncodedQuery?.data(using: .utf8) else {
            throw SlackWebAPIError.apiError("getUploadURL 参数编码失败")
        }
        var getReq = URLRequest(url: URL(string: "https://slack.com/api/files.getUploadURLExternal")!)
        getReq.httpMethod = "POST"
        getReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        getReq.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        getReq.httpBody = getQuery
        let (getData, getResp) = try await URLSession.shared.data(for: getReq)
        if let http = getResp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        struct GetUploadEnvelope: Decodable {
            let ok: Bool
            let error: String?
            let uploadUrl: String?
            let fileId: String?
        }
        let getEnv = try dec.decode(GetUploadEnvelope.self, from: getData)
        guard getEnv.ok,
              let uploadURLStr = getEnv.uploadUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !uploadURLStr.isEmpty,
              let uploadURL = URL(string: uploadURLStr),
              let fileId = getEnv.fileId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fileId.isEmpty else {
            let hint = String(data: getData, encoding: .utf8)?.prefix(280) ?? ""
            throw SlackWebAPIError.apiError(
                "files.getUploadURLExternal：\(getEnv.error ?? "失败")\(hint.isEmpty ? "" : "（\(hint)）")"
            )
        }

        // 2) 将文件 POST 到 Slack 返回的上传地址（官方文档：`Content-Type: application/octet-stream` + 原始字节）
        var putReq = URLRequest(url: uploadURL)
        putReq.httpMethod = "POST"
        putReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        putReq.httpBody = fileData
        let (_, upResp) = try await URLSession.shared.data(for: putReq)
        guard let upHttp = upResp as? HTTPURLResponse else {
            throw SlackWebAPIError.apiError("上传坐标图无 HTTP 响应")
        }
        guard (200 ... 299).contains(upHttp.statusCode) else {
            throw SlackWebAPIError.apiError("上传坐标图失败 HTTP \(upHttp.statusCode)")
        }

        // 3) 完成上传并分享到频道 / 线程（官方示例为 `curl --form`，用 multipart 最贴近 Slack 期望；`files` 值为 JSON 数组文本）
        let filesMeta: [[String: String]] = [["id": fileId, "title": filename]]
        let filesJSONBytes = try JSONSerialization.data(withJSONObject: filesMeta)
        guard let filesJSONString = String(data: filesJSONBytes, encoding: .utf8) else {
            throw SlackWebAPIError.apiError("files 元数据编码失败")
        }

        let completeBoundary = "CompleteBoundary-\(UUID().uuidString)"
        var completeMultipart = Data()
        func appendCompleteField(name: String, value: String) {
            completeMultipart.append("--\(completeBoundary)\r\n".data(using: .utf8)!)
            completeMultipart.append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!
            )
            completeMultipart.append(value.data(using: .utf8)!)
            completeMultipart.append("\r\n".data(using: .utf8)!)
        }
        appendCompleteField(name: "files", value: filesJSONString)
        appendCompleteField(name: "channel_id", value: channel)
        if let ts = threadTs?.trimmingCharacters(in: .whitespacesAndNewlines), !ts.isEmpty {
            appendCompleteField(name: "thread_ts", value: ts)
        }
        if let c = initialComment?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            appendCompleteField(name: "initial_comment", value: c)
        }
        completeMultipart.append("--\(completeBoundary)--\r\n".data(using: .utf8)!)

        var completeReq = URLRequest(url: URL(string: "https://slack.com/api/files.completeUploadExternal")!)
        completeReq.httpMethod = "POST"
        completeReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        completeReq.setValue(
            "multipart/form-data; boundary=\(completeBoundary)",
            forHTTPHeaderField: "Content-Type"
        )
        completeReq.httpBody = completeMultipart
        let (completeData, completeResp) = try await URLSession.shared.data(for: completeReq)
        if let http = completeResp as? HTTPURLResponse, http.statusCode == 429 {
            throw SlackWebAPIError.rateLimited(retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? nil)
        }
        struct CompleteEnvelope: Decodable {
            let ok: Bool
            let error: String?
        }
        let completeEnv = try dec.decode(CompleteEnvelope.self, from: completeData)
        guard completeEnv.ok else {
            let hint = String(data: completeData, encoding: .utf8)?.prefix(280) ?? ""
            throw SlackWebAPIError.apiError(
                "files.completeUploadExternal：\(completeEnv.error ?? "失败")\(hint.isEmpty ? "" : "（\(hint)）")"
            )
        }
        return completeData
    }
}
