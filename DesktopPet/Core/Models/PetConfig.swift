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
}
