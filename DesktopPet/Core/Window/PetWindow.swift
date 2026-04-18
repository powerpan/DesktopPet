//
// PetWindow.swift
// 桌宠浮动面板：无边框、非激活也可显示、透明背景，层级为 floating，可跨 Space 显示。
//

import AppKit

final class PetWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        // 避免桌宠出现在「窗口」菜单里干扰用户
        isExcludedFromWindowsMenu = true
        // 关闭自动窗口状态恢复，减少与 NSSecureCoding / NSXPCDecoder 相关的系统控制台告警概率
        isRestorable = false
    }

    /// 非激活面板基类默认不可成为 key 时，点击内嵌 SwiftUI 按钮仍会触发 `makeKeyWindow`，控制台告警。此处允许在必要时成为 key，与 `becomesKeyOnlyIfNeeded = true` 配合。
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}
