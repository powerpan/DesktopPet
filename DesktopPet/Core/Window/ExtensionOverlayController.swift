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
    /// 供 `layoutTriggerBubble` 重建 SwiftUI 内容与尾巴参数。
    private var bubbleSpeechText: String = ""
    private var bubbleContinueChat: (() -> Void)?

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
        w.title = "智能体工作台"
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

        bubbleSpeechText = trimmed
        bubbleContinueChat = onContinueChat

        let tap: () -> Void = { [weak self] in
            guard let self else { return }
            let cont = self.bubbleContinueChat
            self.dismissTriggerBubble()
            cont?()
        }
        // 先用默认尾巴测量 intrinsic，再由 layoutTriggerBubble 选象限并替换为最终视图。
        let provisional = TriggerSpeechBubbleView(text: trimmed, tailEdge: .bottom, tailAlongOffset: 0, onTap: tap)
        let hosting = NSHostingView(rootView: provisional)
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
        bubbleContinueChat = nil
        bubbleSpeechText = ""
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
              let content = panel.contentView,
              !bubbleSpeechText.isEmpty else { return }

        let margin: CGFloat = 10
        /// 气泡面板矩形与宠窗边沿的间距（AppKit 坐标）；取 0 让尾巴尽量贴住宠窗顶边。
        let gap: CGFloat = 0
        let vf = pet.screen?.visibleFrame ?? ScreenGeometry.visibleFrameContainingMouse()
        let pf = pet.frame

        content.layoutSubtreeIfNeeded()
        var w = content.fittingSize.width
        var h = content.fittingSize.height
        if !w.isFinite || w < 1 { w = 160 }
        if !h.isFinite || h < 1 { h = 72 }
        // 勿再加大 `fittingSize`：多余宽高会让 NSHostingView 内 SwiftUI 左上对齐，右侧与底部出现「假空白」，文字右缘发空、尾巴离宠窗变远。
        w = min(320, max(96, ceil(w)))
        h = min(380, max(52, ceil(h)))
        content.frame = NSRect(x: 0, y: 0, width: w, height: h)
        content.autoresizingMask = [.width, .height]
        content.layoutSubtreeIfNeeded()

        let (originRaw, tailEdge) = BubblePlacementEngine.pickBestOrigin(
            petFrame: pf,
            visibleFrame: vf,
            bubbleSize: CGSize(width: w, height: h),
            margin: margin,
            gap: gap
        )
        let origin = ScreenGeometry.clampedOrigin(CGSize(width: w, height: h), origin: originRaw, in: vf, margin: margin)
        let bubbleFrame = CGRect(origin: origin, size: CGSize(width: w, height: h))
        let tailAlong0 = BubblePlacementEngine.tailAlongOffset(
            petFrame: pf,
            bubbleFrame: bubbleFrame,
            edge: tailEdge,
            bubbleWidth: w,
            bubbleHeight: h
        )

        let tap: () -> Void = { [weak self] in
            guard let self else { return }
            let cont = self.bubbleContinueChat
            self.dismissTriggerBubble()
            cont?()
        }
        let measureView = TriggerSpeechBubbleView(
            text: bubbleSpeechText,
            tailEdge: tailEdge,
            tailAlongOffset: tailAlong0,
            onTap: tap
        )
        let hosting = NSHostingView(rootView: measureView)
        hosting.setFrameSize(NSSize(width: 400, height: 400))
        hosting.layoutSubtreeIfNeeded()
        var w2 = hosting.fittingSize.width
        var h2 = hosting.fittingSize.height
        if !w2.isFinite || w2 < 1 { w2 = w }
        if !h2.isFinite || h2 < 1 { h2 = h }
        w2 = min(320, max(96, ceil(w2)))
        h2 = min(380, max(52, ceil(h2)))
        hosting.frame = NSRect(x: 0, y: 0, width: w2, height: h2)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.masksToBounds = false
        hosting.layoutSubtreeIfNeeded()

        let origin2 = ScreenGeometry.clampedOrigin(CGSize(width: w2, height: h2), origin: originRaw, in: vf, margin: margin)
        let bubbleFrame2 = CGRect(origin: origin2, size: CGSize(width: w2, height: h2))
        let tailAlong2 = BubblePlacementEngine.tailAlongOffset(
            petFrame: pf,
            bubbleFrame: bubbleFrame2,
            edge: tailEdge,
            bubbleWidth: w2,
            bubbleHeight: h2
        )
        let refined = TriggerSpeechBubbleView(
            text: bubbleSpeechText,
            tailEdge: tailEdge,
            tailAlongOffset: tailAlong2,
            onTap: tap
        )
        let hostFinal = NSHostingView(rootView: refined)
        hostFinal.frame = NSRect(x: 0, y: 0, width: w2, height: h2)
        hostFinal.autoresizingMask = [.width, .height]
        hostFinal.wantsLayer = true
        hostFinal.layer?.isOpaque = false
        hostFinal.layer?.backgroundColor = NSColor.clear.cgColor
        hostFinal.layer?.masksToBounds = false
        panel.contentView = hostFinal
        panel.setFrame(NSRect(origin: origin2, size: NSSize(width: w2, height: h2)), display: true)
    }
}

// MARK: - 气泡候选布局（不挡猫猫、靠边象限、尾巴指向）

private enum BubblePlacementEngine {
    private static let nearThreshold: CGFloat = 130

    /// 返回未夹紧的 origin（左下角）与尾巴附着边。
    static func pickBestOrigin(
        petFrame pf: CGRect,
        visibleFrame vf: CGRect,
        bubbleSize: CGSize,
        margin: CGFloat,
        gap: CGFloat
    ) -> (CGPoint, TriggerBubbleTailEdge) {
        let w = bubbleSize.width
        let h = bubbleSize.height
        let candidates = orderedCandidates(petFrame: pf, vf: vf, w: w, h: h, gap: gap)
        var seen = Set<String>()
        var best: (score: CGFloat, origin: CGPoint, edge: TriggerBubbleTailEdge)?

        let catCenter = CGPoint(x: pf.midX, y: pf.midY)

        for (o, e) in candidates {
            let key = "\(Int(o.x * 2))_\(Int(o.y * 2))_\(e.rawValue)"
            if seen.contains(key) { continue }
            seen.insert(key)

            let oc = ScreenGeometry.clampedOrigin(CGSize(width: w, height: h), origin: o, in: vf, margin: margin)
            let B = CGRect(origin: oc, size: CGSize(width: w, height: h))
            let inter = intersectionArea(B, pf)
            let outside = outsideVisibleArea(B, vf)
            let dist = hypot((oc.x + w / 2) - catCenter.x, (oc.y + h / 2) - catCenter.y)
            let distDefault = abs(oc.x - (pf.midX - w / 2)) + abs(oc.y - (pf.maxY + gap))
            // 优先不重叠；其次少越界；再次更贴近默认「上方居中」；最后离猫中心略近
            let score = inter * 1_000_000 + outside * 1_000 + distDefault * 0.02 + dist * 0.001

            if best == nil || score < best!.score {
                best = (score: score, origin: o, edge: e)
            }
        }

        guard let b = best else {
            return (CGPoint(x: pf.midX - w / 2, y: pf.maxY + gap), .bottom)
        }
        return (b.origin, b.edge)
    }

    static func tailAlongOffset(
        petFrame pf: CGRect,
        bubbleFrame B: CGRect,
        edge: TriggerBubbleTailEdge,
        bubbleWidth w: CGFloat,
        bubbleHeight h: CGFloat
    ) -> CGFloat {
        let m: CGFloat = 12
        switch edge {
        case .bottom, .top:
            let local = pf.midX - B.minX
            let hi = max(m, w - m)
            let c = min(max(local, m), hi)
            return c - w / 2
        case .left, .right:
            let local = pf.midY - B.minY
            let hi = max(m, h - m)
            let c = min(max(local, m), hi)
            return c - h / 2
        }
    }

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        guard !r.isNull, !r.isEmpty else { return 0 }
        return r.width * r.height
    }

    private static func outsideVisibleArea(_ r: CGRect, _ vf: CGRect) -> CGFloat {
        let i = r.intersection(vf)
        guard !i.isNull, !i.isEmpty else { return r.width * r.height }
        return max(0, r.width * r.height - i.width * i.height)
    }

    private static func orderedCandidates(
        petFrame pf: CGRect,
        vf: CGRect,
        w: CGFloat,
        h: CGFloat,
        gap: CGFloat
    ) -> [(CGPoint, TriggerBubbleTailEdge)] {
        let midX = pf.midX
        let midY = pf.midY
        let nearRight = vf.maxX - pf.maxX < nearThreshold
        let nearTop = vf.maxY - pf.maxY < nearThreshold
        let nearBottom = pf.minY - vf.minY < nearThreshold
        let nearLeft = pf.minX - vf.minX < nearThreshold

        var list: [(CGPoint, TriggerBubbleTailEdge)] = []

        if nearRight, nearTop {
            list.append((CGPoint(x: pf.minX - gap - w, y: pf.minY - gap - h), .top))
            list.append((CGPoint(x: pf.minX - gap - w, y: pf.maxY + gap), .bottom))
        } else if nearRight {
            list.append((CGPoint(x: pf.minX - gap - w, y: pf.maxY + gap), .bottom))
            list.append((CGPoint(x: pf.minX - gap - w, y: midY - h / 2), .right))
        } else if nearLeft {
            list.append((CGPoint(x: pf.maxX + gap, y: pf.maxY + gap), .bottom))
            list.append((CGPoint(x: pf.maxX + gap, y: midY - h / 2), .left))
        } else if nearTop {
            list.append((CGPoint(x: midX - w / 2, y: pf.minY - gap - h), .top))
        } else if nearBottom {
            list.append((CGPoint(x: midX - w / 2, y: pf.maxY + gap), .bottom))
        }

        list.append((CGPoint(x: midX - w / 2, y: pf.maxY + gap), .bottom))
        list.append((CGPoint(x: midX - w / 2, y: pf.minY - gap - h), .top))
        list.append((CGPoint(x: pf.minX - gap - w, y: midY - h / 2), .right))
        list.append((CGPoint(x: pf.maxX + gap, y: midY - h / 2), .left))
        list.append((CGPoint(x: pf.minX - gap - w, y: pf.maxY + gap), .bottom))
        list.append((CGPoint(x: pf.minX - gap - w, y: pf.minY - gap - h), .top))
        list.append((CGPoint(x: pf.maxX + gap, y: pf.maxY + gap), .bottom))
        list.append((CGPoint(x: pf.maxX + gap, y: pf.minY - gap - h), .top))

        return list
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
