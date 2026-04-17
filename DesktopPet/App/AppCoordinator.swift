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

    private var petWindowController: PetWindowController?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var idleSleepTimer: Timer?
    private var isPetVisible = true

    func start() {
        preparePetWindow()
        wirePermissionAndInput()
        wireSettingsToWindow()
        wirePatrol()
        wireMouse()
        wireActivationRefresh()

        permissionManager.refreshStatus(prompt: false)
        mouseTracker.start()

        if !permissionManager.isGranted {
            presentOnboardingWindow()
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
    }

    func presentOnboardingWindow() {
        if onboardingWindow == nil {
            let view = AccessibilityOnboardingView(permissionManager: permissionManager)
            let hosting = NSHostingView(rootView: view)
            let rect = NSRect(x: 0, y: 0, width: 480, height: 280)
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
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func preparePetWindow() {
        guard petWindowController == nil else { return }
        let controller = PetWindowController(settings: settingsViewModel, stateMachine: stateMachine)
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
                    self.globalInput.start()
                    self.dismissOnboardingIfNeeded()
                } else {
                    self.globalInput.stop()
                }
            }
            .store(in: &cancellables)
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
            self.bumpActivity()
        }
    }

    private func wireActivationRefresh() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.permissionManager.refreshStatus(prompt: false)
            }
            .store(in: &cancellables)
    }

    private func bumpActivity() {
        idleSleepTimer?.invalidate()
        guard stateMachine.state != .sleep else { return }
        idleSleepTimer = Timer.scheduledTimer(
            withTimeInterval: PetConfig.default.idleToSleepInterval,
            repeats: false
        ) { [weak self] _ in
            self?.stateMachine.handle(.idleTimeout)
        }
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
