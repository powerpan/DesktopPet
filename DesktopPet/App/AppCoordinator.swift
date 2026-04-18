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
    let pointerTrackingModel = PointerTrackingModel()

    private var petWindowController: PetWindowController?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    /// 空闲一段时间后触发「进入睡眠」
    private var idleSleepTimer: Timer?
    private var isPetVisible = true
    /// 辅助功能信任轮询：系统设置勾选后 TCC 可能延迟数秒才对本进程生效，取消旧任务避免重复排队。
    private var accessibilityTrustPollTask: Task<Void, Never>?

    func start() {
        preparePetWindow()
        wirePermissionAndInput()
        wireSettingsToWindow()
        wirePatrol()
        wireMouse()
        wireActivationRefresh()
        wireAccessibilityRecheck()

        permissionManager.refreshStatus(prompt: false)
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
        patrolScheduler.stop()
        mouseTracker.stop()
        globalInput.stop()
        idleSleepTimer?.invalidate()
        idleSleepTimer = nil
    }

    func togglePetVisibility() {
        isPetVisible.toggle()
        petWindowController?.setPetVisible(isPetVisible)
        mouseTracker.interactionSamplingEnabled = isPetVisible
        if !isPetVisible {
            pointerTrackingModel.updateGaze(mouseScreen: .zero, petFrame: nil)
        }
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
        let controller = PetWindowController(settings: settingsViewModel, stateMachine: stateMachine, pointer: pointerTrackingModel)
        controller.showWindow(nil)
        petWindowController = controller
    }

    private func wirePermissionAndInput() {
        permissionManager.$isGranted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                guard let self else { return }
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
        globalInput.onKeyDown = { [weak self] _ in
            guard let self else { return }
            self.stateMachine.handle(.keyboardInput)
            self.bumpActivity()
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
        mouseTracker.onPointerScreenLocation = { [weak self] point in
            guard let self else { return }
            self.pointerTrackingModel.updateGaze(
                mouseScreen: point,
                petFrame: self.petWindowController?.window?.frame
            )
        }
        mouseTracker.onInteraction = { [weak self] event in
            guard let self else { return }
            self.stateMachine.handle(event)
            self.bumpActivity()
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
