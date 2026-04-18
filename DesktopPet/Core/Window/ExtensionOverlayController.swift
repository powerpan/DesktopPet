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

    func dismissChatPanel() {
        chatPanel?.orderOut(nil)
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
        presentChatPanel(root: root)
    }

    /// 始终打开/前置聊天面板（用于从触发气泡续聊，避免 `toggle` 误关已打开的面板）。
    func presentChatPanel(root: AnyView) {
        ensureChatPanel()
        chatPanel?.contentView = NSHostingView(rootView: root)
        layoutChatPanel()
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
    /// - Parameter onContinueChat: 用户轻点气泡后：先收起气泡，再执行（例如新建会话并打开聊天窗）。
    func showTriggerBubble(text: String, onContinueChat: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ensureBubblePanel()
        guard let panel = bubblePanel else { return }

        bubbleDismissTimer?.invalidate()
        bubbleDismissTimer = nil

        let view = TriggerSpeechBubbleView(text: trimmed) { [weak self] in
            self?.dismissTriggerBubble()
            onContinueChat?()
        }
        let hosting = NSHostingView(rootView: view)
        // 先给足够大的临时尺寸以便 SwiftUI 算出紧凑的 fittingSize；最终框由 layoutTriggerBubble 决定。
        hosting.setFrameSize(NSSize(width: 360, height: 400))
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.masksToBounds = false
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
        // 系统按窗体矩形画阴影时，透明气泡四角常出现深色「直角框」；阴影改由 SwiftUI 绘制。
        p.hasShadow = false
        p.titlebarAppearsTransparent = true
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
        if !w.isFinite || w < 1 { w = 160 }
        if !h.isFinite || h < 1 { h = 72 }
        // 紧凑：随内容变窄变矮；为下行笔画与阴影留垂直余量，避免第二行被裁切。
        w = min(320, max(96, w + 8))
        h = min(380, max(52, h + 18))
        // 与面板可视区域一致，避免 NSHostingView 大于窗体时出现直角底板或底部裁切。
        content.frame = NSRect(x: 0, y: 0, width: w, height: h)
        content.autoresizingMask = [.width, .height]
        content.layoutSubtreeIfNeeded()

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
