//
// ScreenGeometry.swift
// 屏幕几何工具：根据鼠标位置选取合适的可见桌面矩形，并把窗口原点限制在可见区内。
//

import AppKit
import CoreGraphics

enum ScreenGeometry {
    /// 返回「包含当前鼠标」的屏幕的 visibleFrame（排除菜单栏与 Dock）
    static func visibleFrameContainingMouse() -> CGRect {
        let mousePoint = NSEvent.mouseLocation
        let screens = NSScreen.screens
        // 多数情况下 mouse 落在 screen.frame 内
        if let screen = screens.first(where: { $0.frame.contains(mousePoint) }) {
            return screen.visibleFrame
        }
        // 菜单栏顶部等可能不在 frame 内但仍属于某屏 visibleFrame
        if let screen = screens.first(where: { $0.visibleFrame.contains(mousePoint) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
    }

    static func clampedPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    /// AppKit 窗口坐标：原点在左下角，将 origin 限制在 visibleFrame 内并留边距
    static func clampedOrigin(_ windowSize: CGSize, origin: CGPoint, in visibleFrame: CGRect, margin: CGFloat) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - windowSize.width - margin
        let maxY = visibleFrame.maxY - windowSize.height - margin
        if maxX < minX || maxY < minY {
            return CGPoint(x: minX, y: minY)
        }
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }
}
