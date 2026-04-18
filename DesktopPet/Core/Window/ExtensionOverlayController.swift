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
    private var bubblePanel: NSPanel?
    private var bubbleDismissTimer: Timer?
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
        if bubblePanel?.contentView != nil, bubblePanel?.isVisible == true { layoutTriggerBubble() }
    }

    /// 条件触发旁白：云朵气泡挂在宠窗附近；靠近屏幕右下时改挂到猫猫左上侧。
    func showTriggerBubble(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ensureBubblePanel()
        guard let panel = bubblePanel else { return }

        bubbleDismissTimer?.invalidate()
        bubbleDismissTimer = nil

        let view = TriggerSpeechBubbleView(text: trimmed) { [weak self] in
            self?.dismissTriggerBubble()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(NSSize(width: 280, height: 200))
        panel.contentView = hosting
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        layoutTriggerBubble()

        bubbleDismissTimer = Timer.scheduledTimer(withTimeInterval: 14, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissTriggerBubble()
            }
        }
        if let t = bubbleDismissTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    func dismissTriggerBubble() {
        bubbleDismissTimer?.invalidate()
        bubbleDismissTimer = nil
        bubblePanel?.orderOut(nil)
    }

    private func ensureBubblePanel() {
        guard bubblePanel == nil else { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.isRestorable = false
        p.hidesOnDeactivate = false
        bubblePanel = p
    }

    private func layoutTriggerBubble() {
        guard let panel = bubblePanel,
              let pet = petWindow,
              let content = panel.contentView else { return }

        let margin: CGFloat = 10
        let gap: CGFloat = 8
        let vf = pet.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        content.layoutSubtreeIfNeeded()
        var w = content.fittingSize.width
        var h = content.fittingSize.height
        if !w.isFinite || w < 80 { w = 280 }
        if !h.isFinite || h < 48 { h = 160 }
        w = min(288, max(200, w + 16))
        h = min(200, max(88, h + 12))

        let pf = pet.frame
        let nearRight = (vf.maxX - pf.maxX) < 130
        let nearBottom = (pf.minY - vf.minY) < 130
        let preferUpperLeft = nearRight && nearBottom

        let rawX: CGFloat
        if preferUpperLeft {
            rawX = pf.minX - w + 40
        } else {
            rawX = pf.midX - w / 2
        }
        let x = min(max(rawX, vf.minX + margin), vf.maxX - w - margin)
        var y = pf.maxY + gap
        if y + h > vf.maxY - margin {
            y = vf.maxY - margin - h
        }
        y = max(y, vf.minY + margin)
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
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
