//
// SettingsFloatingButton.swift
// 宠物窗口右上角小按钮：切换「鼠标穿透」开关，图标随状态变化。
//

import SwiftUI

struct SettingsFloatingButton: View {
    @Binding var isClickThrough: Bool
    var liquidGlassChromeEnabled: Bool
    var liquidGlassVariant: DesktopPetLiquidGlassVariant

    var body: some View {
        Button {
            isClickThrough.toggle()
        } label: {
            Image(systemName: isClickThrough ? "hand.tap.fill" : "hand.raised.fill")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .desktopPetControlLiquidGlass(
            liquidGlassEnabled: liquidGlassChromeEnabled,
            glassVariant: liquidGlassVariant
        )
        .contentShape(Rectangle())
        .help(isClickThrough ? "点击：关闭穿透（可拖宠物）" : "点击：开启穿透（点击穿透到下层）")
        .padding(.top, 3)
        .padding(.trailing, 3)
    }
}
