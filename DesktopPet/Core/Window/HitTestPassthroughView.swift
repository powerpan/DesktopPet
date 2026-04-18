//
// HitTestPassthroughView.swift
// 通用穿透视图：开启时整视图不参与命中测试（事件穿透）；当前工程主要逻辑在 PetRootContainerView。
//

import AppKit

final class HitTestPassthroughView: NSView {
    var isPassthroughEnabled = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPassthroughEnabled ? nil : super.hitTest(point)
    }
}
