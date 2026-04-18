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

    /// 窗口需容纳 SwiftUI 卡片区（见 `petCanvasLayoutPoints`）再乘以最大缩放 `petScaleMax`，故默认给足边距。
    static let `default` = PetConfig(
        windowSize: CGSize(width: 400, height: 400),
        patrolInterval: 12,
        idleToSleepInterval: 180
    )

    /// SwiftUI 中宠物卡片基准边长（略小于原 220pt，降低对周边可点区域的影响）。
    static let petCanvasLayoutPoints: CGFloat = 176

    /// 设置里「宠物缩放」滑条范围；上限 1.2 使整窗最大约等于此前 1.2× 时的体量，不再拉到 1.8。
    static let petScaleMin: Double = 0.6
    static let petScaleMax: Double = 1.2

    /// 相对早期 220pt 卡片，整体再乘此系数；**滑条在 1.0 时**视觉与窗口约等于「以前滑条 0.6」的外框（不是把默认滑条改成 0.6）。
    static let visualBaselineFactor: CGFloat = 0.6

    /// 与 SwiftUI 视觉一致：`petCanvasLayoutPoints × scale × visualBaselineFactor`（与 `scaleEffect` 合成系数一致），仅加少量 slack；**不再**叠加大块 `chrome`，否则 1.2 满档时窗外仍有一圈「空窗」挡点击。
    static func exteriorHitSide(scale: Double) -> CGFloat {
        let s = CGFloat(min(max(scale, petScaleMin), petScaleMax))
        let visualSide = petCanvasLayoutPoints * s * visualBaselineFactor
        let slack: CGFloat = 14
        return max(80, ceil(visualSide + slack))
    }
}
