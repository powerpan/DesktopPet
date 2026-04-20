//
// PetWindowController.swift
// 宠物窗口控制器：组装 SwiftUI 根视图与穿透容器，负责巡逻时移动窗口、显隐与穿透开关。
//

import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    private let settings: SettingsViewModel
    private weak var passthroughRoot: PetRootContainerView?
    private var cancellables = Set<AnyCancellable>()
    /// 拖动缩放滑条期间固定用「第一次变化前」的窗口中心，避免每帧用 setFrame 后的 frame 重算中心导致舍入漂移（宠物往右下跑飞屏）。
    private var petScaleResizeAnchorScreen: CGPoint?
    /// 上一次巡逻落点（窗口原点），用于与下一次随机采样拉开距离，减轻总在同一角/边徘徊。
    private var lastPatrolOrigin: CGPoint?

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

        root.refreshHostedSwiftUIDisplay()

        applyPetWindowNSAppearance()
        settings.$colorSchemePreference
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPetWindowNSAppearance()
            }
            .store(in: &cancellables)

        settings.$liquidGlassVariant
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.passthroughRoot?.refreshHostedSwiftUIDisplay()
            }
            .store(in: &cancellables)

        settings.$isLiquidGlassChromeEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.passthroughRoot?.refreshHostedSwiftUIDisplay()
            }
            .store(in: &cancellables)

        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: window),
            NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification, object: window)
        )
        .debounce(for: .milliseconds(40), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.passthroughRoot?.refreshHostedSwiftUIDisplay()
        }
        .store(in: &cancellables)

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

    private func applyPetWindowNSAppearance() {
        window?.appearance = settings.colorSchemePreference.nsAppearanceForAppKitWindows
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
        passthroughRoot?.refreshHostedSwiftUIDisplay()
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
        let sz = window.frame.size
        let margin = CGFloat(
            min(max(settings.patrolEdgeMargin, PetConfig.patrolEdgeMarginMin), PetConfig.patrolEdgeMarginMax)
        )
        let k = min(100, max(0, settings.patrolFrontWindowBiasPercent))
        /// 每 tick 掷骰：`k/100` 概率在「前台区域」矩形（与调试红框同源）内对原点均匀随机；否则强制落在红外。
        let pInRed = Double(k) / 100.0

        let raw = ScreenGeometry.randomPatrolWindowOrigin(
            windowSize: sz,
            in: visibleFrame,
            margin: margin,
            lastOrigin: lastPatrolOrigin,
            minDistanceFromLast: max(28, min(sz.width, sz.height) * 0.12)
        )

        let myPID = ProcessInfo.processInfo.processIdentifier
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - sz.width - margin
        let maxY = visibleFrame.maxY - sz.height - margin
        let minDist = max(28, min(sz.width, sz.height) * 0.12)

        var blended = raw
        if maxX >= minX, maxY >= minY {
            let red = ScreenGeometry.patrolObstacleForAvoidance(patrolVisibleFrame: visibleFrame, excludingPID: myPID)
            let roll = Double.random(in: 0...1)
            if roll < pInRed, let region = red {
                blended = ScreenGeometry.randomPatrolWindowOriginInsideRect(
                    windowSize: sz,
                    inside: region,
                    in: visibleFrame,
                    margin: margin,
                    lastOrigin: lastPatrolOrigin,
                    minDistanceFromLast: minDist
                )
            } else if let region = red {
                let avoid = ScreenGeometry.randomPatrolWindowOriginOutsideFrontRect(
                    windowSize: sz,
                    in: visibleFrame,
                    margin: margin,
                    lastOrigin: lastPatrolOrigin,
                    minDistanceFromLast: minDist,
                    obstacle: region,
                    clearance: 8,
                    allowPartialFallback: false
                )
                blended = avoid
                let petBlended = CGRect(origin: blended, size: sz)
                let block = region.insetBy(dx: -8, dy: -8)
                if petBlended.intersects(block) {
                    blended = ScreenGeometry.patrolClampOriginClearOfObstacle(
                        windowSize: sz,
                        origin: blended,
                        in: visibleFrame,
                        margin: margin,
                        obstacle: region,
                        clearance: 8
                    )
                }
            } else {
                blended = raw
            }
        }

        let newOrigin = ScreenGeometry.clampedOrigin(sz, origin: blended, in: visibleFrame, margin: margin)
        lastPatrolOrigin = newOrigin
        var nextFrame = window.frame
        let prevOrigin = nextFrame.origin
        nextFrame.origin = newOrigin
        let travel = hypot(newOrigin.x - prevOrigin.x, newOrigin.y - prevOrigin.y)
        guard travel > 0.5 else { return }

        // 保留平滑移动：`setFrame(..., animate: true)` 在部分系统上与透明窗 `glassEffect` 合成偶发冲突；
        // 用 `NSAnimationContext` 走 `animator()`，在动画结束后再刷新 Hosting，减轻「像退回磨砂」且不牺牲位移动画。
        let duration = min(0.48, max(0.2, travel / 720))
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(nextFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.passthroughRoot?.refreshHostedSwiftUIDisplay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.passthroughRoot?.refreshHostedSwiftUIDisplay()
            }
        })
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
