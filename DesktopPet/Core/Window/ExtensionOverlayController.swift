//
// ExtensionOverlayController.swift
// 饲养 / 聊天叠加面板：锚定在宠物窗口附近，菜单栏控制显隐。
//

import AppKit
import SwiftUI

@MainActor
final class ExtensionOverlayController {
    private weak var petWindow: NSWindow?
    private var carePanel: NSPanel?
    private var chatPanel: NSPanel?
    private var agentSettingsWindow: NSWindow?

    func attachPetWindow(_ window: NSWindow?) {
        petWindow = window
    }

    func isCareVisible() -> Bool {
        carePanel?.isVisible == true
    }

    func isChatVisible() -> Bool {
        chatPanel?.isVisible == true
    }

    func toggleCarePanel(root: AnyView) {
        if let p = carePanel, p.isVisible {
            p.orderOut(nil)
            return
        }
        ensureCarePanel()
        carePanel?.contentView = NSHostingView(rootView: root)
        layoutCarePanel()
        carePanel?.orderFrontRegardless()
    }

    func toggleChatPanel(root: AnyView) {
        if let p = chatPanel, p.isVisible {
            p.orderOut(nil)
            return
        }
        ensureChatPanel()
        chatPanel?.contentView = NSHostingView(rootView: root)
        layoutChatPanel()
        // 菜单栏 accessory 应用 + 可输入面板：需激活应用并让面板成为 key，TextField 才能接收键盘。
        NSApp.activate(ignoringOtherApps: true)
        chatPanel?.makeKeyAndOrderFront(nil)
    }

    func presentAgentSettings(root: AnyView) {
        if let w = agentSettingsWindow {
            w.contentView = NSHostingView(rootView: root)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let rect = NSRect(x: 0, y: 0, width: 520, height: 620)
        let w = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "智能体设置"
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        agentSettingsWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    private func ensureCarePanel() {
        guard carePanel == nil else { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = NSColor.clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.isRestorable = false
        carePanel = p
    }

    private func ensureChatPanel() {
        guard chatPanel == nil else { return }
        let p = KeyableBorderlessPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = NSColor.clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isRestorable = false
        chatPanel = p
    }

    private func layoutCarePanel() {
        guard let panel = carePanel, let win = petWindow else { return }
        let pf = win.frame
        let w: CGFloat = min(320, max(220, pf.width))
        let h: CGFloat = 200
        let origin = NSPoint(x: pf.midX - w / 2, y: pf.minY - h - 8)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
    }

    private func layoutChatPanel() {
        guard let panel = chatPanel, let win = petWindow else { return }
        let pf = win.frame
        let w: CGFloat = min(360, max(280, pf.width + 40))
        let h: CGFloat = 420
        let origin = NSPoint(x: pf.maxX + 8, y: pf.midY - h / 2)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
    }

    func repositionIfNeeded() {
        if carePanel?.isVisible == true { layoutCarePanel() }
        if chatPanel?.isVisible == true { layoutChatPanel() }
    }
}

// MARK: - 可输入的浮动面板

/// 默认 `NSPanel` 往往 `canBecomeKey == false`，内嵌 SwiftUI `TextField` 无法获得键盘焦点；与 `PetWindow` 同理显式允许成为 key。
private final class KeyableBorderlessPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isRestorable = false
    }
}
