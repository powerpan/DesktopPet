//
// ScreenGeometry.swift
// 屏幕几何工具：根据鼠标位置选取合适的可见桌面矩形，并把窗口原点限制在可见区内。
//

import AppKit
import CoreGraphics

/// 启用巡逻时，宠物随机落点所限制的显示器范围（菜单栏「DesktopPet」设置）。
enum PatrolRegionMode: String, CaseIterable, Identifiable, Codable {
    /// 仅在 `NSScreen.main` 的可见桌面内巡逻。
    case mainOnly = "main"
    /// 仅在外接等非主屏上巡逻；若无外接屏则退回主屏。
    case secondaryOnly = "secondary"
    /// 每次巡逻 tick 在已连接显示器中随机选一屏的可见区（主 + 副）。
    case mainAndSecondary = "all"

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .mainOnly: return "仅主屏"
        case .secondaryOnly: return "仅副屏"
        case .mainAndSecondary: return "主屏 + 副屏"
        }
    }
}

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

    /// 巡逻用：按设置选取一块「可见桌面」`visibleFrame`（不含菜单栏与 Dock）。
    static func visibleFrameForPatrol(mode: PatrolRegionMode) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return .zero }
        let main = NSScreen.main ?? screens[0]
        let nonMain = screens.filter { $0 !== main }

        switch mode {
        case .mainOnly:
            return main.visibleFrame
        case .secondaryOnly:
            if let s = nonMain.randomElement() ?? nonMain.first {
                return s.visibleFrame
            }
            return main.visibleFrame
        case .mainAndSecondary:
            return (screens.randomElement() ?? main).visibleFrame
        }
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

    /// 尝试取「前台其他应用」的主窗口外框（Quartz 屏幕坐标，与 `NSWindow.frame` / `NSEvent.mouseLocation` 一致）。
    /// 用于巡逻时偶尔贴近活动窗口顶部；若系统未返回可用数据则返回 nil。
    static func approximateFrontmostAppWindowFrame(excludingPID: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in info {
            let ownerPID = pid_t((entry["kCGWindowOwnerPID"] as? NSNumber)?.int32Value ?? 0)
            if ownerPID == excludingPID { continue }

            let layer = (entry["kCGWindowLayer"] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }

            if let alphaNum = entry["kCGWindowAlpha"] as? NSNumber, alphaNum.doubleValue < 0.05 {
                continue
            }

            guard let boundsDict = entry["kCGWindowBounds"] as? [String: Any] else {
                continue
            }
            let x = (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if w < 180 || h < 120 { continue }
            if rect.isEmpty || rect.isInfinite || rect.isNull { continue }
            return rect
        }
        return nil
    }
}
