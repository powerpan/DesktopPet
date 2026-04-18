//
// SettingsFloatingButton.swift
// 宠物窗口右上角小按钮：切换「鼠标穿透」开关，图标随状态变化。
//

import SwiftUI

struct SettingsFloatingButton: View {
    @Binding var isClickThrough: Bool

    var body: some View {
        Button {
            isClickThrough.toggle()
        } label: {
            Image(systemName: isClickThrough ? "hand.tap.fill" : "hand.raised.fill")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .help(isClickThrough ? "当前穿透：开" : "当前穿透：关")
        .padding(6)
    }
}
