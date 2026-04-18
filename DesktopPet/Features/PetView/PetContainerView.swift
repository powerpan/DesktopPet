//
// PetContainerView.swift
// 桌宠 SwiftUI 根布局：精灵占位 + 穿透切换浮动按钮，整体可缩放。
//

import SwiftUI

struct PetContainerView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var stateMachine: PetStateMachine

    var body: some View {
        // 不用 ZStack(alignment: .topTrailing) 叠精灵+按钮：在「未铺满」时会把精灵贴右上角，左下出现大块空白（预览里像一圈缝）。
        // 缩放体现在 `frame` 边长（`petLayoutSide`），不用 `scaleEffect`：后者只缩绘制、布局仍为 176，Preview 蓝框与卡片之间会出现一圈空白。
        PetSpriteView()
            .frame(
                width: PetConfig.petLayoutSide(scale: settings.petScale),
                height: PetConfig.petLayoutSide(scale: settings.petScale)
            )
            .overlay(alignment: .topTrailing) {
                SettingsFloatingButton(
                    isClickThrough: Binding(
                        get: { settings.isClickThroughEnabled },
                        set: { settings.isClickThroughEnabled = $0 }
                    )
                )
            }
            .animation(.easeInOut(duration: 0.2), value: settings.petScale)
    }
}

#Preview {
    let desk = DeskMirrorModel()
    desk.setAccessibilityKeyboardMirrorGranted(true)
    return PetContainerView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PetStateMachine())
        .environmentObject(PointerTrackingModel())
        .environmentObject(desk)
}
