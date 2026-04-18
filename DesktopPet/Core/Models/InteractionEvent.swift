//
// InteractionEvent.swift
// 用户与桌宠相关的输入与定时事件枚举，由鼠标/键盘/巡逻/空闲逻辑投递给状态机。
//

import CoreGraphics

enum InteractionEvent {
    case keyboardInput
    case mouseMovedFast(speed: CGFloat)
    case mouseHoverNear(distance: CGFloat)
    case patrolRequested
    case idleTimeout
}
