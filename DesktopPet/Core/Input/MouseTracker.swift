//
// MouseTracker.swift
// 定时采样鼠标位置：检测快速移动与靠近宠物窗口，并节流后上报为 InteractionEvent。
//

import AppKit
import Foundation

@MainActor
final class MouseTracker {
    private var timer: Timer?
    /// 为 false 时（例如宠物已隐藏）仍跑定时器但不派发事件，避免屏外光标误触发状态。
    var interactionSamplingEnabled = true
    var onInteraction: ((InteractionEvent) -> Void)?
    /// 由协调器提供当前宠物窗口 frame，用于计算悬停距离。
    var petFrameProvider: (() -> CGRect?)?
    private var lastLocation: CGPoint = .zero
    private var lastHoverEmit: TimeInterval = 0
    private let hoverThrottle: TimeInterval = 0.25
    private var lastPointerEmit: TimeInterval = 0
    private let pointerEmitInterval: TimeInterval = 1.0 / 24.0
    /// 用于「注视」等纯展示层：屏幕坐标，与 `NSEvent.mouseLocation` 一致。
    var onPointerScreenLocation: ((CGPoint) -> Void)?
    /// 与上一次采样的屏幕坐标差分（`NSEvent.mouseLocation` 系：x 右为正，y **上**为正）；用于桌前鼠标垫镜像。
    var onMouseDeltaScreen: ((CGVector) -> Void)?

    func start() {
        guard timer == nil else { return }
        lastLocation = NSEvent.mouseLocation
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Logger.shared.info("Mouse tracker started.")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Logger.shared.info("Mouse tracker stopped.")
    }

    private func sample() {
        let current = NSEvent.mouseLocation
        let dx = current.x - lastLocation.x
        let dy = current.y - lastLocation.y
        if interactionSamplingEnabled {
            onMouseDeltaScreen?(CGVector(dx: dx, dy: dy))
        }
        guard interactionSamplingEnabled else {
            lastLocation = current
            return
        }
        let speed = sqrt(dx * dx + dy * dy)
        lastLocation = current

        let pointerNow = ProcessInfo.processInfo.systemUptime
        if interactionSamplingEnabled, pointerNow - lastPointerEmit >= pointerEmitInterval {
            lastPointerEmit = pointerNow
            onPointerScreenLocation?(current)
        }

        // 单次采样间隔内位移过大视为「快速甩动」
        if speed > 80 {
            onInteraction?(.mouseMovedFast(speed: speed))
            return
        }

        if let frame = petFrameProvider?() {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let distance = hypot(current.x - center.x, current.y - center.y)
            if distance < 120 {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastHoverEmit >= hoverThrottle {
                    lastHoverEmit = now
                    onInteraction?(.mouseHoverNear(distance: distance))
                }
            }
        }
    }
}
