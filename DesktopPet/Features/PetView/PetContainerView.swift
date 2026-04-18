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
        .padding(8)
        .frame(width: 220, height: 220)
        .scaleEffect(settings.petScale)
        .animation(.easeInOut(duration: 0.2), value: settings.petScale)
    }
}

#Preview {
    PetContainerView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PetStateMachine())
        .environmentObject(PointerTrackingModel())
}
