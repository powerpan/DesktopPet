//
// PetRootContainerView.swift
// AppKit 根视图：承载 SwiftUI 内容；开启穿透时除右上角控件区域外 hitTest 返回 nil，让点击落到下层窗口。
//

import AppKit
import SwiftUI

final class PetRootContainerView: NSView {
    private let hostingView: NSHostingView<AnyView>

    /// 与 `PetConfig.exteriorHitSide` 一致；仅在此矩形（相对本视图 bounds 居中）内接收点击，矩形外 `hitTest` 一律返回 nil，事件落到下层应用。
    var hitClipSidePoints: CGFloat = PetConfig.exteriorHitSide(scale: 1.0) {
        didSet { needsDisplay = true }
    }

    var passthroughEnabled = true {
        didSet { needsDisplay = true }
    }

    init<V: View>(rootView: V) {
        hostingView = NSHostingView(rootView: AnyView(rootView))
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 与 SwiftUI 一致采用向下增长的 Y，便于和 .topTrailing 对齐命中区域
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let b = bounds
        let side = min(hitClipSidePoints, min(b.width, b.height))
        guard side > 1 else {
            return super.hitTest(point)
        }
        let env = CGRect(
            x: (b.width - side) * 0.5,
            y: (b.height - side) * 0.5,
            width: side,
            height: side
        )
        if !env.contains(point) {
            return nil
        }

        let local = hostingView.convert(point, from: self)
        if passthroughEnabled {
            let hit = hostingView.hitTest(local)
            // SwiftUI 在空白区有时仍命中 NSHostingView 自身，等价于无控件 → 让事件落到下层
            if hit === hostingView { return nil }
            return hit
        }
        return hostingView.hitTest(local) ?? hostingView
    }
}
