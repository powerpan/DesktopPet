//
// PetConfig.swift
// 桌宠可调参数集中定义：窗口默认尺寸、巡逻间隔、空闲多久进入睡眠等。
//

import CoreGraphics
import Foundation

struct PetConfig {
    var windowSize: CGSize
    var patrolInterval: TimeInterval
    var idleToSleepInterval: TimeInterval

    /// 窗口需容纳 SwiftUI 内容区 220×220 再乘以最大缩放 1.8，故默认给足边距。
    static let `default` = PetConfig(
        windowSize: CGSize(width: 400, height: 400),
        patrolInterval: 12,
        idleToSleepInterval: 180
    )

    /// 相对早期 220pt 卡片，整体再乘此系数；**滑条在 1.0 时**视觉与窗口约等于「以前滑条 0.6」的外框（不是把默认滑条改成 0.6）。
    static let visualBaselineFactor: CGFloat = 0.6

    /// 与 `PetContainerView` 的 `frame(220) + scaleEffect(scale * visualBaselineFactor)` 一致；用作窗口边长与 `PetRootContainerView` 命中裁剪。
    static func exteriorHitSide(scale: Double) -> CGFloat {
        let s = CGFloat(min(max(scale, 0.6), 1.8))
        let base: CGFloat = 220 * visualBaselineFactor
        let chrome: CGFloat = 48
        return max(100, base * s + chrome)
    }
}
