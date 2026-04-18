//
// PetContainerView.swift
// 桌宠 SwiftUI 根布局：精灵占位 + 穿透切换浮动按钮，整体可缩放。
//

import SwiftUI

struct PetContainerView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var stateMachine: PetStateMachine

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PetSpriteView()
            SettingsFloatingButton(
                isClickThrough: Binding(
                    get: { settings.isClickThroughEnabled },
                    set: { settings.isClickThroughEnabled = $0 }
                )
            )
        }
        // 不要在这里再包一层 .padding：会扩大布局/命中基底，窗口只能跟着变大，形成「隐形外圈」。
        .frame(width: PetConfig.petCanvasLayoutPoints, height: PetConfig.petCanvasLayoutPoints)
        .scaleEffect(settings.petScale * PetConfig.visualBaselineFactor)
        .animation(.easeInOut(duration: 0.2), value: settings.petScale)
    }
}

#Preview {
    PetContainerView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PetStateMachine())
        .environmentObject(PointerTrackingModel())
}
