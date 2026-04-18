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
        chatPanel?.orderFrontRegardless()
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
        carePanel = p
    }

    private func ensureChatPanel() {
        guard chatPanel == nil else { return }
        let p = NSPanel(
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
