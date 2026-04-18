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

    /// SwiftUI 卡片实际布局边长（已含滑条与 `visualBaselineFactor`）。应用层请用此值做 `frame`，**勿**再对整块内容 `scaleEffect`：后者不改变布局尺寸，会在 Preview/命中基底周围留下一圈与缩放成比例的空白。
    static func petLayoutSide(scale: Double) -> CGFloat {
        let s = CGFloat(min(max(scale, petScaleMin), petScaleMax))
        return petCanvasLayoutPoints * s * visualBaselineFactor
    }

    /// 窗口与 `PetRootContainerView.hitClipSidePoints`：`petLayoutSide` + **slack**（舍入、右上角按钮、圆角抗锯齿与缩放时内容边距），避免裁切圆角。
    static func exteriorHitSide(scale: Double) -> CGFloat {
        let visualSide = petLayoutSide(scale: scale)
        let slack: CGFloat = 14
        return max(72, ceil(visualSide + slack))
    }
}
