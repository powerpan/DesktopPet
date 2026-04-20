//
// DesktopPetChrome.swift
// 宠物卡片与浮层：macOS 26+ 使用 `glassEffect` + Apple `Glass`（regular / clear / tint）；低版本用材质；并与 `NSWindow.appearance` 搭配避免浅色主题下仍按深色解析。
//

import AppKit
import SwiftUI

enum DesktopPetChrome {
    /// 大面板背景：磨砂材质或窗口级底色（用于 macOS 14…25 回退）。
    @ViewBuilder
    static func panelFill<S: Shape>(_ shape: S, liquidGlass: Bool) -> some View {
        if liquidGlass {
            shape.fill(.ultraThinMaterial)
        } else {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// 小控件：`.regularMaterial` 或控件槽底色（用于 macOS 14…25 回退）。
    @ViewBuilder
    static func controlFill<S: Shape>(_ shape: S, liquidGlass: Bool) -> some View {
        if liquidGlass {
            shape.fill(.regularMaterial)
        } else {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Apple `Glass`（仅 macOS 26+；官方可调主要为变体、`tint`、`interactive`）

extension DesktopPetLiquidGlassVariant {
    /// 大圆角矩形、气泡主体、气泡尾巴等与面板一致的 `Glass`。
    @available(macOS 26.0, *)
    var swiftUIPanelGlass: Glass {
        switch self {
        case .regular:
            return .regular
        case .clear:
            return .clear
        case .tinted:
            return .regular.tint(Color.primary.opacity(0.09))
        }
    }

    /// 小圆形控件：略开 `interactive` 以符合系统控件反馈。
    @available(macOS 26.0, *)
    var swiftUIControlGlass: Glass {
        switch self {
        case .regular:
            return .regular.interactive()
        case .clear:
            return .clear.interactive()
        case .tinted:
            return .regular.tint(Color.primary.opacity(0.1)).interactive()
        }
    }
}

extension View {
    /// 圆角矩形大面板。
    func desktopPetPanelLiquidGlass(
        cornerRadius: CGFloat,
        liquidGlassEnabled: Bool,
        glassVariant: DesktopPetLiquidGlassVariant
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return Group {
            if !liquidGlassEnabled {
                self.background {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                }
            } else if #available(macOS 26.0, *) {
                self
                    .background {
                        if glassVariant == .clear {
                            shape.fill(Color.primary.opacity(0.1))
                        }
                    }
                    .glassEffect(glassVariant.swiftUIPanelGlass, in: shape)
            } else {
                self.background {
                    shape.fill(.ultraThinMaterial)
                }
            }
        }
    }

    /// 圆形小控件。
    func desktopPetControlLiquidGlass(
        liquidGlassEnabled: Bool,
        glassVariant: DesktopPetLiquidGlassVariant
    ) -> some View {
        Group {
            if !liquidGlassEnabled {
                self.background {
                    Circle().fill(Color(nsColor: .controlBackgroundColor))
                }
            } else if #available(macOS 26.0, *) {
                self.glassEffect(glassVariant.swiftUIControlGlass, in: Circle())
            } else {
                self.background {
                    Circle().fill(.regularMaterial)
                }
            }
        }
    }
}
