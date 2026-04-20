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
    /// 对话 / Slack 多模态附件大小上限（「集成」Tab 可调）。
    let multimodalAttachmentLimitsStore = MultimodalAttachmentLimitsStore()
    let slackSyncController = SlackSyncController()
    let screenWatchTaskStore = ScreenWatchTaskStore()
    let screenWatchEventStore = ScreenWatchEventStore()
    private lazy var screenWatchRunner = ScreenWatchRunner(tasks: screenWatchTaskStore, events: screenWatchEventStore)
    private let frontmostAppWatcher = FrontmostAppWatcher()
    private let overlayHostController = ExtensionOverlayController()
    private lazy var appRouter = DesktopPetAppRouter(overlay: overlayHostController)
    let routeBus = AppRouteBus()
    private let agentClient = AgentClient()
    private lazy var screenWatchHitFeedback = ScreenWatchHitFeedbackService(
        agentSessionStore: agentSessionStore,
        agentSettingsStore: agentSettingsStore,
        agentClient: agentClient,
        slackSyncController: slackSyncController,
        deliverTriggerSpeech: { [weak self] payload in
            self?.deliverTriggerSpeech(payload)
        }
    )

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
        wirePetWindowOverlayNotifications()
        wireRouteBus()
        wirePresentAgentSettingsTabNotificationBridge()
        wireSlackInboundAutoReply()

        petCareModel.configureGrowthEngine(client: agentClient, settings: agentSettingsStore)
        petCareModel.onPetStatNarrativeRequest = { [weak self] line in
            guard let self else { return false }
            return await self.triggerEngine.firePetStatAutomationNarrative(contextLine: line)
        }
        petCareModel.startCompanionTicking { [weak self] in self?.isPetVisible ?? false }
        triggerEngine.start()

        slackSyncController.start(
            session: agentSessionStore,
            screenWatchTasks: screenWatchTaskStore,
            agentClient: agentClient,
            agentSettings: agentSettingsStore,
            multimodalLimits: multimodalAttachmentLimitsStore,
            accessibilityPermission: permissionManager
        )
        screenWatchRunner.start(agentClient: agentClient, agentSettings: agentSettingsStore) { [weak self] task, _, kind in
            self?.screenWatchHitFeedback.notifyHit(task: task, narrativeKind: kind)
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
        appRouter.dismissTriggerBubble()
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
            appRouter.dismissTriggerBubble()
        }
    }

    func toggleCareOverlay() {
        appRouter.toggleCarePanel(root: AnyView(
            CareOverlayView()
                .environmentObject(petCareModel)
                .environmentObject(agentSettingsStore)
                .environmentObject(routeBus)
        ))
    }

    func toggleChatOverlay() {
        let wasVisible = appRouter.isChatVisible()
        appRouter.toggleChatPanel(root: chatOverlayRoot())
        // 从隐藏变为显示时清掉旧错误，避免「已保存 Key 却仍显示未配置」的误导（lastError 来自上次发送失败）。
        if appRouter.isChatVisible(), !wasVisible {
            agentSessionStore.lastError = nil
        }
    }

    /// 打开或前置对话面板（不切换关闭）；用于触发气泡点击后续聊。
    /// - Parameter clearLastError: 为 `false` 时保留 `lastError`（例如菜单截屏失败后需要展示原因）。
    func presentChatOverlay(clearLastError: Bool = true) {
        appRouter.presentChatPanel(root: chatOverlayRoot())
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
                .environmentObject(routeBus)
                .environmentObject(multimodalAttachmentLimitsStore)
                .environment(\.desktopPetAgentClient, agentClient)
        )
    }

    func presentAgentSettingsWindow() {
        appRouter.presentAgentSettings(root: AnyView(
            AgentSettingsView()
                .environmentObject(agentSettingsStore)
                .environmentObject(agentSessionStore)
                .environmentObject(petCareModel)
                .environmentObject(slackSyncController)
                .environmentObject(screenWatchTaskStore)
                .environmentObject(screenWatchEventStore)
                .environmentObject(multimodalAttachmentLimitsStore)
                .environmentObject(routeBus)
                .environmentObject(settingsViewModel)
                .environment(\.desktopPetAgentClient, agentClient)
        ))
    }

    func presentOnboardingWindow() {
        if onboardingWindow == nil {
            let view = AccessibilityOnboardingView(permissionManager: permissionManager)
                .environmentObject(routeBus)
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
        appRouter.attachPetWindow(controller.window, settings: settingsViewModel)
    }

    private func wirePetWindowOverlayNotifications() {
        guard let window = petWindowController?.window else { return }
        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: window),
            NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.appRouter.repositionOverlaysIfNeeded()
        }
        .store(in: &cancellables)
    }

    /// 兼容仍通过 `NotificationCenter` 投递的「打开设置并切 Tab」路径，统一走 `AppRouteBus`。
    private func wirePresentAgentSettingsTabNotificationBridge() {
        NotificationCenter.default.publisher(for: .desktopPetPresentAgentSettingsTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                let raw = note.userInfo?[DesktopPetNotificationUserInfoKey.agentSettingsTabIndex] as? Int ?? 0
                let workspace = AgentSettingsWorkspaceTab.workspaceIndex(fromLegacySevenTabIndex: raw)
                self.routeBus.presentAgentSettingsTab(index: workspace)
            }
            .store(in: &cancellables)
    }

    private func wireRouteBus() {
        routeBus.onCloseChatOverlay = { [weak self] in
            self?.appRouter.dismissChatPanel()
        }
        routeBus.onCloseCareOverlay = { [weak self] in
            self?.appRouter.dismissCarePanel()
        }
        routeBus.onPresentChatContinuingChannel = { [weak self] id in
            guard let self else { return }
            self.agentSessionStore.selectChannel(id: id)
            self.presentChatOverlay()
        }
        routeBus.onPresentAgentSettingsTab = { [weak self] tab in
            guard let self else { return }
            UserDefaults.standard.set(tab, forKey: "DesktopPet.ui.pendingAgentSettingsTab.v2")
            self.presentAgentSettingsWindow()
        }
        routeBus.onForceFireTriggerRuleJSON = { [weak self] json in
            guard let self else { return }
            guard let data = json.data(using: .utf8),
                  let rule = try? JSONDecoder().decode(AgentTriggerRule.self, from: data) else { return }
            Task { @MainActor in
                await self.triggerEngine.forceFireTrigger(ruleSnapshot: rule)
            }
        }
        routeBus.onCareInteractionNarrative = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in
                await self.triggerEngine.fireCareInteractionNarrative(contextLine: line)
            }
        }
        routeBus.onAccessibilityRecheck = { [weak self] in
            self?.recheckAccessibilityAndRestartInput()
        }
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
                    let svc = SlackInboundAutoReplyService(
                        slackSync: self.slackSyncController,
                        session: self.agentSessionStore,
                        settings: self.agentSettingsStore,
                        deskMirror: self.deskMirrorModel,
                        client: self.agentClient,
                        multimodalLimits: self.multimodalAttachmentLimitsStore
                    )
                    await svc.performAutoReplyIfPossible(channelId: channelId)
                }
            }
            .store(in: &cancellables)
    }

    /// 条件触发或测试气泡：写入旁白历史并展示云朵（点气泡可续聊）。
    private func deliverTriggerSpeech(_ payload: TriggerSpeechPayload) {
        agentSessionStore.triggerHistory.append(
            text: payload.text,
            kind: payload.triggerKind,
            userPrompt: payload.userPrompt,
            snapshotJPEG: payload.requestSnapshotJPEG
        )
        appRouter.showTriggerBubble(text: payload.text) { [weak self] in
            guard let self else { return }
            self.agentSessionStore.startSessionFromTrigger(text: payload.text)
            self.presentChatOverlay()
        }
        if payload.notifySlack {
            Task { @MainActor in
                await slackSyncController.postTriggerNarrativeToSlack(triggerKind: payload.triggerKind, text: payload.text)
            }
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

        Publishers.Merge(
            settingsViewModel.$petScale.dropFirst().map { _ in },
            settingsViewModel.$triggerBubbleFontScale.dropFirst().map { _ in }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.appRouter.repositionOverlaysIfNeeded()
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
            let patrolFrame = ScreenGeometry.visibleFrameForPatrol(mode: self.settingsViewModel.patrolRegionMode)
            self.petWindowController?.nudgePatrolStep(in: patrolFrame)
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
