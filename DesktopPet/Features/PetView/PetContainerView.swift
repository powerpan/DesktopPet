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
        // 精灵先铺满固定画布，再用 overlay 叠按钮，布局与命中都与 176×176 对齐。
        PetSpriteView()
            .frame(width: PetConfig.petCanvasLayoutPoints, height: PetConfig.petCanvasLayoutPoints)
            .overlay(alignment: .topTrailing) {
                SettingsFloatingButton(
                    isClickThrough: Binding(
                        get: { settings.isClickThroughEnabled },
                        set: { settings.isClickThroughEnabled = $0 }
                    )
                )
            }
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
