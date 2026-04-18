//
// PetRootContainerView.swift
// AppKit 根视图：承载 SwiftUI 内容；开启穿透时除右上角控件区域外 hitTest 返回 nil，让点击落到下层窗口。
//

import AppKit
import SwiftUI

final class PetRootContainerView: NSView {
    private let hostingView: NSHostingView<AnyView>

    var passthroughEnabled = true {
        didSet { needsDisplay = true }
    }

    private let controlPadding: CGFloat = 6
    private let controlSize: CGFloat = 44

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

    /// 与 SwiftUI `.topTrailing` 的「视觉右上角」对齐：flipped 视图里对应 y 较小的那一侧
    private func controlBounds(in bounds: CGRect) -> CGRect {
        let w = bounds.width
        let side = controlPadding + controlSize
        return CGRect(x: w - side, y: 0, width: side, height: side)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passthroughEnabled {
            let rect = controlBounds(in: bounds)
            if rect.contains(point) {
                let local = hostingView.convert(point, from: self)
                return hostingView.hitTest(local)
            }
            return nil
        }
        let local = hostingView.convert(point, from: self)
        return hostingView.hitTest(local)
    }
}
