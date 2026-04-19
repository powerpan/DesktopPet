//
// AppCoordinator.swift
// 应用中枢：创建宠物浮动窗与权限说明窗，串联辅助功能、全局键盘、鼠标采样、巡逻、设置与宠物状态机。
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    let permissionManager = AccessibilityPermissionManager()
    let globalInput = GlobalInputMonitor()
    let mouseTracker = MouseTracker()
    let stateMachine = PetStateMachine()
    let patrolScheduler = PatrolScheduler()
    let settingsViewModel = SettingsViewModel()
    let deskMirrorModel = DeskMirrorModel()
    let petCareModel = PetCareModel()
    let agentSettingsStore = AgentSettingsStore()
    let agentSessionStore = AgentSessionStore()
    let slackSyncController = SlackSyncController()
    let screenWatchTaskStore = ScreenWatchTaskStore()
    let screenWatchEventStore = ScreenWatchEventStore()
    private lazy var screenWatchRunner = ScreenWatchRunner(tasks: screenWatchTaskStore, events: screenWatchEventStore)
    private let frontmostAppWatcher = FrontmostAppWatcher()
    private let extensionOverlay = ExtensionOverlayController()
    private let agentClient = AgentClient()

    private lazy var triggerEngine = AgentTriggerEngine(
        settings: agentSettingsStore,
        session: agentSessionStore,
        client: agentClient,
        deskMirror: deskMirrorModel,
        frontWatcher: frontmostAppWatcher,
        isPetVisible: { [weak self] in self?.isPetVisible ?? false },
        onTriggerSpeech: { [weak self] payload in
            self?.deliverTriggerSpeech(payload)
        }
    )

    private var petWindowController: PetWindowController?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    /// 空闲一段时间后触发「进入睡眠」
    private var idleSleepTimer: Timer?
    private var isPetVisible = true
    /// 辅助功能信任轮询：系统设置勾选后 TCC 可能延迟数秒才对本进程生效，取消旧任务避免重复排队。
    private var accessibilityTrustPollTask: Task<Void, Never>?
    /// Slack 入站后自动请求模型：串行执行，避免同轮询里多条消息并发抢 `isSending`。
    private var slackAutoReplyChain: Task<Void, Never>?

    func start() {
        preparePetWindow()
        wirePermissionAndInput()
        wireSettingsToWindow()
        wirePatrol()
        wireMouse()
        wireActivationRefresh()
        wireAccessibilityRecheck()
        wirePetWindowOverlayNotifications()
        wirePresentChatContinuingChannelFromSettings()
        wireCloseChatOverlayFromPanel()
        wireForceFireTriggerFromSettings()
        wireCareInteractionFromPetPanel()
        wirePresentAgentSettingsTabFromNotification()
        wireSlackInboundAutoReply()

        petCareModel.configureGrowthEngine(client: agentClient, settings: agentSettingsStore)
        petCareModel.startCompanionTicking { [weak self] in self?.isPetVisible ?? false }
        triggerEngine.start()

        slackSyncController.start(
            session: agentSessionStore,
            screenWatchTasks: screenWatchTaskStore,
            agentClient: agentClient,
            agentSettings: agentSettingsStore
        )
        screenWatchRunner.start(agentClient: agentClient, agentSettings: agentSettingsStore) { [weak self] task, detail, kind in
            self?.notifyScreenWatchHit(task: task, detail: detail, narrativeKind: kind)
        }

        permissionManager.refreshStatus(prompt: false)
        deskMirrorModel.setAccessibilityKeyboardMirrorGranted(permissionManager.isGranted)
        // 隐藏宠物时不应因屏外鼠标产生悬停/唤醒
        mouseTracker.interactionSamplingEnabled = isPetVisible
        mouseTracker.start()

        // 若用户已预先勾选辅助功能，Combine 可能不会发「从 false→true」，需主动启动监听
        if permissionManager.isGranted {
            configureGlobalInputHandlers()
            globalInput.restart()
        }

        if !permissionManager.isGranted {
            presentOnboardingWindow()
            // 登记调度在 `presentOnboardingWindow()` 末尾统一触发，避免重复排队
        }

        petWindowController?.setPassthrough(settingsViewModel.isClickThroughEnabled)
        petWindowController?.setPetVisible(isPetVisible)
        bumpActivity()
    }

    func stop() {
        extensionOverlay.dismissTriggerBubble()
        patrolScheduler.stop()
        mouseTracker.stop()
        globalInput.stop()
        triggerEngine.stop()
        slackSyncController.stop()
        screenWatchRunner.stop()
        petCareModel.stopCompanionTicking()
        idleSleepTimer?.invalidate()
        idleSleepTimer = nil
    }

    func togglePetVisibility() {
        isPetVisible.toggle()
        petWindowController?.setPetVisible(isPetVisible)
        mouseTracker.interactionSamplingEnabled = isPetVisible
        if !isPetVisible {
            deskMirrorModel.resetMouseMirror()
            extensionOverlay.dismissTriggerBubble()
        }
    }

    func toggleCareOverlay() {
        extensionOverlay.toggleCarePanel(root: AnyView(
            CareOverlayView()
                .environmentObject(petCareModel)
        ))
    }

    func toggleChatOverlay() {
        let wasVisible = extensionOverlay.isChatVisible()
        extensionOverlay.toggleChatPanel(root: chatOverlayRoot())
        // 从隐藏变为显示时清掉旧错误，避免「已保存 Key 却仍显示未配置」的误导（lastError 来自上次发送失败）。
        if extensionOverlay.isChatVisible(), !wasVisible {
            agentSessionStore.lastError = nil
        }
    }

    /// 打开或前置对话面板（不切换关闭）；用于触发气泡点击后续聊。
    /// - Parameter clearLastError: 为 `false` 时保留 `lastError`（例如菜单截屏失败后需要展示原因）。
    func presentChatOverlay(clearLastError: Bool = true) {
        extensionOverlay.presentChatPanel(root: chatOverlayRoot())
        if clearLastError {
            agentSessionStore.lastError = nil
        }
    }

    private func chatOverlayRoot() -> AnyView {
        AnyView(
            ChatOverlayView()
                .environmentObject(agentSessionStore)
                .environmentObject(agentSettingsStore)
                .environmentObject(deskMirrorModel)
        )
    }

    func presentAgentSettingsWindow() {
        extensionOverlay.presentAgentSettings(root: AnyView(
            AgentSettingsView()
                .environmentObject(agentSettingsStore)
                .environmentObject(agentSessionStore)
                .environmentObject(petCareModel)
                .environmentObject(slackSyncController)
                .environmentObject(screenWatchTaskStore)
                .environmentObject(screenWatchEventStore)
                .environment(\.desktopPetAgentClient, agentClient)
        ))
    }

    func presentOnboardingWindow() {
        if onboardingWindow == nil {
            let view = AccessibilityOnboardingView(permissionManager: permissionManager)
            let hosting = NSHostingView(rootView: view)
            let rect = NSRect(x: 0, y: 0, width: 500, height: 360)
            let window = NSWindow(
                contentRect: rect,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "DesktopPet 权限"
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            onboardingWindow = window
            // 用户手动关窗后清空引用，否则无法再次从菜单打开
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
                .prefix(1)
                .sink { [weak self] _ in
                    if self?.onboardingWindow === window {
                        self?.onboardingWindow = nil
                    }
                }
                .store(in: &cancellables)
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        if !permissionManager.isGranted {
            permissionManager.scheduleAccessibilityListingRegistrationPromptIfNeeded()
        }
    }

    private func preparePetWindow() {
        guard petWindowController == nil else { return }
        let controller = PetWindowController(
            settings: settingsViewModel,
            stateMachine: stateMachine,
            deskMirror: deskMirrorModel
        )
        controller.showWindow(nil)
        petWindowController = controller
        extensionOverlay.attachPetWindow(controller.window)
    }

    private func wirePetWindowOverlayNotifications() {
        guard let window = petWindowController?.window else { return }
        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: window),
            NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.extensionOverlay.repositionIfNeeded()
        }
        .store(in: &cancellables)
    }

    private func wirePresentChatContinuingChannelFromSettings() {
        NotificationCenter.default.publisher(for: .desktopPetPresentChatContinuingChannel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let idString = note.userInfo?[DesktopPetNotificationUserInfoKey.channelId] as? String,
                      let id = UUID(uuidString: idString) else { return }
                self.agentSessionStore.selectChannel(id: id)
                self.presentChatOverlay()
            }
            .store(in: &cancellables)
    }

    private func wireCloseChatOverlayFromPanel() {
        NotificationCenter.default.publisher(for: .desktopPetCloseChatOverlay)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.extensionOverlay.dismissChatPanel()
            }
            .store(in: &cancellables)
    }

    private func wireForceFireTriggerFromSettings() {
        NotificationCenter.default.publisher(for: .desktopPetForceFireTriggerRule)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let json = note.userInfo?[DesktopPetNotificationUserInfoKey.triggerRuleJSON] as? String,
                      let data = json.data(using: .utf8),
                      let rule = try? JSONDecoder().decode(AgentTriggerRule.self, from: data)
                else { return }
                Task { @MainActor in
                    await self.triggerEngine.forceFireTrigger(ruleSnapshot: rule)
                }
            }
            .store(in: &cancellables)
    }

    /// 菜单栏：对截屏规则执行一次旁白（需隐私总开关 + 屏幕录制权限）；失败时打开对话面板以展示 `lastError`。
    func requestScreenSnapNarrativeFromMenu() {
        Task { @MainActor in
            await self.triggerEngine.fireScreenSnapFromMenuBar()
            if let err = self.agentSessionStore.lastError, !err.isEmpty {
                self.presentChatOverlay(clearLastError: false)
            }
        }
    }

    private func wireCareInteractionFromPetPanel() {
        NotificationCenter.default.publisher(for: .desktopPetCareInteractionForNarrative)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let line = note.userInfo?[DesktopPetNotificationUserInfoKey.careContext] as? String else { return }
                Task { @MainActor in
                    await self.triggerEngine.fireCareInteractionNarrative(contextLine: line)
                }
            }
            .store(in: &cancellables)
    }

    private func wirePresentAgentSettingsTabFromNotification() {
        NotificationCenter.default.publisher(for: .desktopPetPresentAgentSettingsTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                let tab = note.userInfo?[DesktopPetNotificationUserInfoKey.agentSettingsTabIndex] as? Int ?? 0
                let clamped = min(6, max(0, tab))
                UserDefaults.standard.set(clamped, forKey: "DesktopPet.ui.pendingAgentSettingsTab.v2")
                self.presentAgentSettingsWindow()
            }
            .store(in: &cancellables)
    }

    /// Slack 入站写入 `user` 后，用当前「连接」里的模型对该**频道**自动续写一条 `assistant`（与对话面板逻辑一致，并会经出站同步回 Slack）。
    private func wireSlackInboundAutoReply() {
        NotificationCenter.default.publisher(for: .desktopPetConversationDidAppendMessage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard (note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendOrigin] as? String) == "slack" else { return }
                guard (note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendRole] as? String) == "user" else { return }
                guard let idStr = note.userInfo?[DesktopPetNotificationUserInfoKey.conversationAppendChannelId] as? String,
                      let channelId = UUID(uuidString: idStr) else { return }
                guard self.slackSyncController.integrationConfig.enabled,
                      self.slackSyncController.integrationConfig.syncInbound else { return }
                let previous = self.slackAutoReplyChain
                self.slackAutoReplyChain = Task { @MainActor [weak self] in
                    await previous?.value
                    guard let self else { return }
                    await self.performSlackInboundAutoReply(channelId: channelId)
                }
            }
            .store(in: &cancellables)
    }

    private func performSlackInboundAutoReply(channelId: UUID) async {
        guard slackSyncController.integrationConfig.enabled else { return }
        if agentSessionStore.isSending { return }
        guard let channel = agentSessionStore.conversation.channel(id: channelId) else { return }

        let key = KeychainStore.readAPIKey(forProvider: agentSettingsStore.activeAPIProvider)
        var systemPrompt = agentSettingsStore.systemPrompt
        systemPrompt += "\n\n（本条或本轮上下文中的部分 user 消息可能来自 Slack；请像平常一样以桌宠身份自然回复。）"
        if agentSettingsStore.attachKeySummary {
            let s = deskMirrorModel.recentKeyLabelsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                systemPrompt += "\n\n（可选上下文）用户近期键入标签摘要：\(s.prefix(200))"
            }
        }

        let apiMessages: [[String: String]] = channel.messages.compactMap { m in
            if m.role == "user" || m.role == "assistant" {
                return ["role": m.role, "content": m.content]
            }
            return nil
        }
        guard apiMessages.contains(where: { $0["role"] == "user" }) else { return }

        agentSessionStore.setSending(true)
        agentSessionStore.lastError = nil
        defer { agentSessionStore.setSending(false) }

        do {
            let reply = try await agentClient.completeChat(
                baseURL: agentSettingsStore.baseURL,
                model: agentSettingsStore.model,
                apiKey: key,
                systemPrompt: systemPrompt,
                messages: apiMessages,
                temperature: agentSettingsStore.temperature,
                maxTokens: agentSettingsStore.maxTokens
            )
            agentSessionStore.appendAssistantInChannel(channelId: channelId, text: reply)
        } catch {
            agentSessionStore.lastError = error.localizedDescription
        }
    }

    private func notifyScreenWatchHit(task: ScreenWatchTask, detail _: String, narrativeKind: ScreenWatchHitNarrativeKind) {
        switch narrativeKind {
        case .visionFallback:
            // 不向用户展示「模型兜底判定：YES」等技术摘要；与本地命中一致，走短旁白（可再调同一连接模型）。
            Task { @MainActor [weak self] in
                guard let self else { return }
                let line = await self.narrateScreenWatchVisionFallbackHit(task: task)
                let text = "【盯屏】\(task.title)\n\(line)"
                self.deliverTriggerSpeech(TriggerSpeechPayload(
                    text: text,
                    triggerKind: .screenWatch,
                    userPrompt: nil,
                    requestSnapshotJPEG: nil
                ))
                self.postSlackScreenWatchHitIfNeeded(task: task, body: text)
            }
        case .localHeuristic:
            Task { @MainActor [weak self] in
                guard let self else { return }
                let line = await self.narrateScreenWatchLocalHeuristicHit(taskTitle: task.title)
                let text = "【盯屏】\(task.title)\n\(line)"
                self.deliverTriggerSpeech(TriggerSpeechPayload(
                    text: text,
                    triggerKind: .screenWatch,
                    userPrompt: nil,
                    requestSnapshotJPEG: nil
                ))
                self.postSlackScreenWatchHitIfNeeded(task: task, body: text)
            }
        }
    }

    /// Slack 自动建任务：在原帖线程汇报命中（与本地气泡文案一致）。
    private func postSlackScreenWatchHitIfNeeded(task: ScreenWatchTask, body: String) {
        guard task.creationSource == .slackAutomated else { return }
        let ch = task.slackReportChannelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ch.isEmpty else { return }
        let thread = task.slackReportThreadTs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadArg: String? = (thread?.isEmpty == false) ? thread : nil
        Task { await slackSyncController.postSlackThreadReply(channelId: ch, threadTs: threadArg, text: body) }
    }

    /// 模型看图兜底命中后的用户文案：与本地命中同一策略——再调模型写口语旁白，不复述 YES/技术 detail。
    private func narrateScreenWatchVisionFallbackHit(task: ScreenWatchTask) async -> String {
        let key = KeychainStore.readAPIKey(forProvider: agentSettingsStore.activeAPIProvider)
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.screenWatchVisionFallbackUserFallbackNarrative()
        }
        let hint = task.visionUserHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let hintLine = hint.isEmpty ? "（用户未单独写看图说明，仅依据任务标题理解。）" : "用户当初让你看图判断的要点：\(hint.prefix(200))"
        do {
            var sys = agentSettingsStore.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sys.isEmpty { sys += "\n\n" }
            sys += """
            （本轮附加指示）用户配置的「盯屏任务」已在本机通过截图、由多模态模型判定为「条件已满足」。
            请你以桌宠身份写 1～2 句简短、口语化的中文，温柔地告诉用户「可以过来看一眼啦」或类似陪伴感；可轻轻呼应任务主题，不必照抄标题全文。
            禁止：出现「YES」「NO」「OCR」「多模态」「截图模型」「兜底」「API」「置信度」等技术词；不要复述模型原始输出；不要分点列举；不要「作为人工智能」式套话。总字数 60 字以内。
            只输出旁白正文，不要加引号，不要加「旁白：」等前缀。
            """
            let user = "任务标题（供你把握语气，不必照抄）：\(task.title)\n\(hintLine)"
            let reply = try await agentClient.completeChat(
                baseURL: agentSettingsStore.baseURL,
                model: agentSettingsStore.model,
                apiKey: key,
                systemPrompt: sys,
                messages: [["role": "user", "content": user]],
                temperature: min(1.0, agentSettingsStore.temperature + 0.15),
                maxTokens: 120
            )
            let line = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return Self.screenWatchVisionFallbackUserFallbackNarrative() }
            return line
        } catch {
            return Self.screenWatchVisionFallbackUserFallbackNarrative()
        }
    }

    private static func screenWatchVisionFallbackUserFallbackNarrative() -> String {
        "图上那边已经对上你要的状态啦，快来看一眼，我在这儿陪你～"
    }

    /// 本地 OCR/亮度命中后的气泡：优先用当前连接模型写一两句自然旁白；无 Key 或请求失败时用柔和兜底（事件列表里仍是技术向 `detail`）。
    private func narrateScreenWatchLocalHeuristicHit(taskTitle: String) async -> String {
        let key = KeychainStore.readAPIKey(forProvider: agentSettingsStore.activeAPIProvider)
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.screenWatchLocalHeuristicFallbackNarrative()
        }
        do {
            var sys = agentSettingsStore.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sys.isEmpty { sys += "\n\n" }
            sys += """
            （本轮附加指示）用户给你配置派遣的「盯屏任务」（帮用户盯着屏幕进度）刚刚在本机判定为条件已满足（依据屏幕上的文字或进度区域变化，未使用截图问答模型）。
            请你以桌宠身份写 1～2 句简短、口语化的中文，让用户感到被陪伴；可以轻轻呼应任务主题，不必机械重复标题全文。
            禁止：出现「OCR」「亮度」「像素」「启发式」「规则」「模型」「API」等技术词；不要分点列举；不要「作为人工智能」式套话。总字数 60 字以内。
            只输出旁白正文，不要加引号，不要加「旁白：」等前缀。
            """
            let user = "任务标题（供你把握语气，不必照抄）：\(taskTitle)"
            let reply = try await agentClient.completeChat(
                baseURL: agentSettingsStore.baseURL,
                model: agentSettingsStore.model,
                apiKey: key,
                systemPrompt: sys,
                messages: [["role": "user", "content": user]],
                temperature: min(1.0, agentSettingsStore.temperature + 0.15),
                maxTokens: 120
            )
            let line = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return Self.screenWatchLocalHeuristicFallbackNarrative() }
            return line
        } catch {
            return Self.screenWatchLocalHeuristicFallbackNarrative()
        }
    }

    private static func screenWatchLocalHeuristicFallbackNarrative() -> String {
        "好啦，你盯的那件事看起来已经满足条件了，我来喊你一声～"
    }

    /// 条件触发或测试气泡：写入旁白历史并展示云朵（点气泡可续聊）。
    private func deliverTriggerSpeech(_ payload: TriggerSpeechPayload) {
        agentSessionStore.triggerHistory.append(
            text: payload.text,
            kind: payload.triggerKind,
            userPrompt: payload.userPrompt,
            snapshotJPEG: payload.requestSnapshotJPEG
        )
        extensionOverlay.showTriggerBubble(text: payload.text) { [weak self] in
            guard let self else { return }
            self.agentSessionStore.startSessionFromTrigger(text: payload.text)
            self.presentChatOverlay()
        }
    }

    private func wirePermissionAndInput() {
        permissionManager.$isGranted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                guard let self else { return }
                self.deskMirrorModel.setAccessibilityKeyboardMirrorGranted(granted)
                if granted {
                    self.configureGlobalInputHandlers()
                    self.globalInput.restart()
                    self.dismissOnboardingIfNeeded()
                } else {
                    self.globalInput.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func wireAccessibilityRecheck() {
        NotificationCenter.default.publisher(for: .desktopPetAccessibilityRecheck)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recheckAccessibilityAndRestartInput()
            }
            .store(in: &cancellables)
    }

    /// 用户点击「重新检测」：强制读 AX、刷新诊断文案，并在已信任时重启键盘监听（修复此前 start 早退导致全局监听永远为 nil）。
    private func recheckAccessibilityAndRestartInput() {
        // 切回前台再读，避免刚在系统设置里勾选时仍读到旧状态
        NSApp.activate(ignoringOtherApps: true)
        permissionManager.refreshStatus(prompt: false, bumpUI: true)
        applyTrustToInputMonitors()
        // 同一轮事件循环末尾再读一次（部分系统上 TCC 与 RunLoop 节拍不同步）
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.permissionManager.refreshStatus(prompt: false, bumpUI: true)
            self.applyTrustToInputMonitors()
        }
        scheduleAccessibilityTrustPollingIfNeeded(manualRecheck: true)
    }

    /// 根据当前辅助功能信任状态，挂接或停止全局键盘监听。
    private func applyTrustToInputMonitors() {
        if permissionManager.isGranted {
            accessibilityTrustPollTask?.cancel()
            accessibilityTrustPollTask = nil
            configureGlobalInputHandlers()
            globalInput.restart()
            dismissOnboardingIfNeeded()
        } else {
            globalInput.stop()
        }
    }

    /// 从系统设置返回或用户点「重新检测」后，TCC 可能延迟数秒才刷新；在未信任时按间隔再检测若干次。
    private func scheduleAccessibilityTrustPollingIfNeeded(manualRecheck: Bool = false) {
        guard !permissionManager.isGranted else { return }
        accessibilityTrustPollTask?.cancel()
        let delays: [Double] = manualRecheck
            ? [0.2, 0.55, 1.1, 2.2, 4.0, 7.0, 10.0]
            : [0.35, 1.0, 2.5, 5.0]
        accessibilityTrustPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in delays {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
                self.permissionManager.refreshStatus(prompt: false, bumpUI: true)
                self.applyTrustToInputMonitors()
                if self.permissionManager.isGranted { return }
            }
        }
    }

    private func configureGlobalInputHandlers() {
        globalInput.onKeyDown = { [weak self] event in
            guard let self else { return }
            self.deskMirrorModel.consumeKeyEvent(
                event,
                mirrorKeysEnabled: self.settingsViewModel.isDeskKeyMirrorEnabled
            )
            self.stateMachine.handle(.keyboardInput)
            self.triggerEngine.handleKeyDownForTriggers(event)
            self.bumpActivity()
        }
        globalInput.onKeyUp = { [weak self] event in
            self?.deskMirrorModel.consumeKeyUpEvent(
                event,
                mirrorKeysEnabled: self?.settingsViewModel.isDeskKeyMirrorEnabled ?? false
            )
        }
        globalInput.onCommandK = { [weak self] in
            guard let self else { return }
            self.togglePetVisibility()
            self.bumpActivity()
        }
    }

    private func wireSettingsToWindow() {
        settingsViewModel.$isClickThroughEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.petWindowController?.setPassthrough(enabled)
            }
            .store(in: &cancellables)
    }

    private func wirePatrol() {
        patrolScheduler.onPatrolTick = { [weak self] in
            guard let self else { return }
            guard self.settingsViewModel.isPatrolEnabled else { return }
            // 隐藏时不再移动窗口，避免不可见仍在「巡逻」
            guard self.isPetVisible else { return }
            self.stateMachine.handle(.patrolRequested)
            self.petWindowController?.nudgePatrolStep(in: ScreenGeometry.visibleFrameContainingMouse())
            self.bumpActivity()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                self.stateMachine.transition(to: .idle)
            }
        }

        settingsViewModel.$isPatrolEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.patrolScheduler.start()
                } else {
                    self.patrolScheduler.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func wireMouse() {
        mouseTracker.petFrameProvider = { [weak self] in
            self?.petWindowController?.window?.frame
        }
        mouseTracker.onInteraction = { [weak self] event in
            guard let self else { return }
            self.stateMachine.handle(event)
            self.triggerEngine.noteUserActivity()
            self.bumpActivity()
        }
        mouseTracker.onMouseDeltaScreen = { [weak self] delta in
            self?.deskMirrorModel.applyMouseDeltaScreen(delta)
        }
    }

    private func wireActivationRefresh() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.permissionManager.refreshStatus(prompt: false, bumpUI: true)
                self.applyTrustToInputMonitors()
                self.scheduleAccessibilityTrustPollingIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func bumpActivity() {
        triggerEngine.noteUserActivity()
        idleSleepTimer?.invalidate()
        if stateMachine.state == .sleep {
            return
        }
        let interval = PetConfig.default.idleToSleepInterval
        idleSleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stateMachine.handle(.idleTimeout)
            }
        }
        // 加入 common 模式，避免在滚动菜单栏等模式下计时器不触发
        if let idleSleepTimer {
            RunLoop.main.add(idleSleepTimer, forMode: .common)
        }
    }

    private func dismissOnboardingIfNeeded() {
        guard permissionManager.isGranted else { return }
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}
