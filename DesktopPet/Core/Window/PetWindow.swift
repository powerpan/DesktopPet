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
    }
}
