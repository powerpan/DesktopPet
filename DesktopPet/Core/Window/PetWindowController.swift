//
// PetWindowController.swift
// 宠物窗口控制器：组装 SwiftUI 根视图与穿透容器，负责巡逻时移动窗口、显隐与穿透开关。
//

import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    private let petConfig = PetConfig.default
    private weak var passthroughRoot: PetRootContainerView?

    init(settings: SettingsViewModel, stateMachine: PetStateMachine) {
        let rect = NSRect(x: 120, y: 240, width: petConfig.windowSize.width, height: petConfig.windowSize.height)
        let window = PetWindow(contentRect: rect)
        let rootView = PetContainerView()
            .environmentObject(settings)
            .environmentObject(stateMachine)
        let root = PetRootContainerView(rootView: rootView)
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
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
        let candidates: [CGPoint] = [
            CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin),
            CGPoint(x: visibleFrame.maxX - frame.width - margin, y: visibleFrame.minY + margin),
            CGPoint(x: visibleFrame.midX - frame.width / 2, y: visibleFrame.maxY - frame.height - margin),
        ]
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
