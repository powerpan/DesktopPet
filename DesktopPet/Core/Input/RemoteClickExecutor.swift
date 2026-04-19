//
// RemoteClickExecutor.swift
// 将归一化坐标（左上原点 0…1）映射到主屏 Quartz 全局坐标并发送左键点击。
//

import AppKit
import CoreGraphics
import Foundation

enum RemoteClickExecutorError: LocalizedError {
    case accessibilityDenied
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "需要「辅助功能」权限才能远程点击。请在系统设置 → 隐私与安全性 → 辅助功能 中允许本应用。"
        case .invalidCoordinate:
            return "坐标无效或越界。"
        }
    }
}

enum RemoteClickExecutor {
    /// 归一化坐标：图像左上为 (0,0)，右下为 (1,1)；`displayBounds` 为 `CGDisplayBounds(main)`。
    static func quartzPoint(
        normX: Double,
        normY: Double,
        displayBounds: CGRect,
        imagePixelSize: CGSize
    ) throws -> CGPoint {
        guard normX >= 0, normX <= 1, normY >= 0, normY <= 1,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            throw RemoteClickExecutorError.invalidCoordinate
        }

        let maxIx = max(0, Double(imagePixelSize.width) - 1)
        let maxIy = max(0, Double(imagePixelSize.height) - 1)
        let ix = min(max(normX * maxIx, 0), maxIx)
        let iy = min(max(normY * maxIy, 0), maxIy)

        let db = displayBounds
        let qx = db.minX + (ix / Double(imagePixelSize.width)) * Double(db.width)
        // 图像 y 向下；Quartz 全局 y 向上
        let qy = db.maxY - (iy / Double(imagePixelSize.height)) * Double(db.height)
        return CGPoint(x: qx, y: qy)
    }

    static func performLeftClick(at quartzPoint: CGPoint, accessibilityTrusted: Bool) throws {
        guard accessibilityTrusted else { throw RemoteClickExecutorError.accessibilityDenied }

        let loc = CGPoint(x: quartzPoint.x, y: quartzPoint.y)

        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: loc, mouseButton: .left),
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: loc, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: loc, mouseButton: .left) else {
            throw RemoteClickExecutorError.invalidCoordinate
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
