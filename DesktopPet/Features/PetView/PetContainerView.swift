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
            // 铺在底层且不参与命中，避免 ZStack 中心空白区仍被 SwiftUI 当成可点容器挡住下层（穿透开启时尤甚）
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            PetSpriteView()
            SettingsFloatingButton(
                isClickThrough: Binding(
                    get: { settings.isClickThroughEnabled },
                    set: { settings.isClickThroughEnabled = $0 }
                )
            )
        }
        .padding(8)
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
