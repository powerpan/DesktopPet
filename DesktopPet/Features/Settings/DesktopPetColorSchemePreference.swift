//
// DesktopPetColorSchemePreference.swift
// 桌宠界面浅色 / 深色 / 跟随系统；用于 SwiftUI `preferredColorScheme` 与 `NSWindow.appearance`。
//

import AppKit
import SwiftUI

enum DesktopPetColorSchemePreference: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 传给 `preferredColorScheme`：`nil` 表示跟随系统。
    var resolvedPreferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 与 `preferredColorScheme` 一致；透明 `NSPanel` 内需同步，否则 `NSColor`/材质仍按系统全局外观解析，浅色主题下宠窗会偏深。
    var nsAppearanceForAppKitWindows: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// macOS 26+ `glassEffect` 的 `Glass` 配置（Apple 提供 `regular` / `clear` 与 `tint` 等链式 API，无单独「模糊强度」滑条）。
enum DesktopPetLiquidGlassVariant: String, CaseIterable, Identifiable, Codable {
    case regular
    case clear
    case tinted

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .regular: return "标准"
        case .clear: return "更透"
        case .tinted: return "淡着色"
        }
    }
}
