//
// MainScreenRegionPicker.swift
// 在主显示器上拖拽框选矩形，用于盯屏「进度条区域」；输出为 NormalizedRect（相对主屏、左上为原点），与截屏 JPEG 的 UV 一致。
//

import AppKit
import SwiftUI

@MainActor
enum MainScreenRegionPicker {
    /// 在主屏上框选一块矩形；取消或失败时 `completion(nil)`。
    static func pickNormalizedRect(completion: @escaping (NormalizedRect?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }
        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .statusBar + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false

        let view = RegionPickFlippedView(frame: NSRect(origin: .zero, size: frame.size)) { norm in
            window.orderOut(nil)
            window.close()
            completion(norm)
        }
        window.contentView = view
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - AppKit 拖拽视图（坐标系：左上为原点，与 NormalizedRect 文档一致）

private final class RegionPickFlippedView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private let onComplete: (NormalizedRect?) -> Void

    init(frame frameRect: NSRect, onComplete: @escaping (NormalizedRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onComplete(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
        guard let a = dragStart else {
            onComplete(nil)
            return
        }
        let b = convert(event.locationInWindow, from: nil)
        let w = bounds.width
        let h = bounds.height
        guard w > 4, h > 4 else {
            onComplete(nil)
            return
        }
        var r = NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
        r = r.intersection(bounds)
        guard r.width >= 8, r.height >= 8 else {
            onComplete(nil)
            return
        }
        let norm = NormalizedRect(
            x: Double(r.minX / w),
            y: Double(r.minY / h),
            width: Double(r.width / w),
            height: Double(r.height / h)
        )
        onComplete(norm)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let a = dragStart, let b = dragCurrent else { return }
        let r = NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
        NSColor.systemBlue.withAlphaComponent(0.35).setFill()
        r.fill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: r)
        path.lineWidth = 2
        path.stroke()
    }
}
