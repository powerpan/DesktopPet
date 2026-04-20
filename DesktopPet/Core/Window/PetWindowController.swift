//
// PetWindowController.swift
// 宠物窗口控制器：组装 SwiftUI 根视图与穿透容器，负责巡逻时移动窗口、显隐与穿透开关。
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    private let settings: SettingsViewModel
    private weak var passthroughRoot: PetRootContainerView?
    private var cancellables = Set<AnyCancellable>()
    /// 拖动缩放滑条期间固定用「第一次变化前」的窗口中心，避免每帧用 setFrame 后的 frame 重算中心导致舍入漂移（宠物往右下跑飞屏）。
    private var petScaleResizeAnchorScreen: CGPoint?

    init(settings: SettingsViewModel, stateMachine: PetStateMachine, deskMirror: DeskMirrorModel) {
        self.settings = settings
        let initialSide = PetConfig.exteriorHitSide(scale: settings.petScale)
        let rect = NSRect(x: 120, y: 240, width: initialSide, height: initialSide)
        let window = PetWindow(contentRect: rect)
        let rootView = PetContainerView()
            .environmentObject(settings)
            .environmentObject(stateMachine)
            .environmentObject(deskMirror)
        let root = PetRootContainerView(rootView: rootView)
        root.hitClipSidePoints = initialSide
        window.contentView = root
        super.init(window: window)
        shouldCascadeWindows = false
        passthroughRoot = root
        window.isReleasedWhenClosed = false
        // 首次出现尽量落在当前鼠标所在屏的安全区内
        let vf = ScreenGeometry.visibleFrameContainingMouse()
        if !vf.isEmpty {
            var f = window.frame
            f.origin = ScreenGeometry.clampedOrigin(f.size, origin: f.origin, in: vf, margin: 24)
            window.setFrameOrigin(f.origin)
        }

        settings.$petScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scale in
                self?.applyWindowSize(forScale: scale)
            }
            .store(in: &cancellables)

        settings.$petScale
            .debounce(for: .milliseconds(160), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.petScaleResizeAnchorScreen = nil
            }
            .store(in: &cancellables)
    }

    private func applyWindowSize(forScale scale: Double) {
        guard let window else { return }
        let side = CGFloat(round(PetConfig.exteriorHitSide(scale: scale)))
        passthroughRoot?.hitClipSidePoints = side
        let newSize = NSSize(width: side, height: side)

        let anchor: CGPoint
        if let a = petScaleResizeAnchorScreen {
            anchor = a
        } else {
            let old = window.frame
            let a = CGPoint(x: old.midX, y: old.midY)
            petScaleResizeAnchorScreen = a
            anchor = a
        }

        var origin = CGPoint(
            x: anchor.x - newSize.width / 2,
            y: anchor.y - newSize.height / 2
        )
        origin.x = round(origin.x * 2) / 2
        origin.y = round(origin.y * 2) / 2

        let vf = window.screen?.visibleFrame ?? ScreenGeometry.visibleFrameContainingMouse()
        origin = ScreenGeometry.clampedOrigin(newSize, origin: origin, in: vf, margin: 12)

        let newFrame = NSRect(origin: origin, size: newSize)
        window.setFrame(newFrame, display: true, animate: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        // 不使用 super：默认实现会对窗口调 makeKeyAndOrderFront，而 .nonactivatingPanel 曾令 canBecomeKeyWindow 为 false 时产生控制台警告。
        window?.orderFrontRegardless()
    }

    func setPassthrough(_ enabled: Bool) {
        passthroughRoot?.passthroughEnabled = enabled
        // 穿透开启时不要用「拖背景移动」，以免与点击穿透冲突；关闭穿透则可拖窗体移动
        window?.isMovableByWindowBackground = !enabled
    }

    func nudgePatrolStep(in visibleFrame: CGRect) {
        guard let window else { return }
        var frame = window.frame
        let margin: CGFloat = 48
        var candidates: [CGPoint] = [
            CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin),
            CGPoint(x: visibleFrame.maxX - frame.width - margin, y: visibleFrame.minY + margin),
            CGPoint(x: visibleFrame.midX - frame.width / 2, y: visibleFrame.maxY - frame.height - margin),
        ]

        let myPID = ProcessInfo.processInfo.processIdentifier
        // 前台窗口若在巡逻区域外（例如在副屏），不要把目标点加进来，否则 clamp 后常贴在主屏边缘、看起来像「往副屏跑」。
        if Double.random(in: 0...1) < 0.5,
           let front = ScreenGeometry.approximateFrontmostAppWindowFrame(excludingPID: myPID),
           visibleFrame.intersects(front) {
            let targetX = front.midX - frame.width / 2
            let targetY = front.maxY - frame.height * 0.12
            candidates.append(CGPoint(x: targetX, y: targetY))
        }

        if let raw = candidates.randomElement() {
            frame.origin = ScreenGeometry.clampedOrigin(frame.size, origin: raw, in: visibleFrame, margin: margin)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    func setPetVisible(_ visible: Bool) {
        guard let window else { return }
        if visible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }
}
