//
// PetContainerView.swift
// 桌宠 SwiftUI 根布局：精灵占位 + 穿透切换浮动按钮，整体可缩放。
//

import SwiftUI

struct PetContainerView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var stateMachine: PetStateMachine

    var body: some View {
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
    let side = PetConfig.petLayoutSide(scale: 1.0)
    return PetContainerView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PetStateMachine())
        .environmentObject(desk)
        // 与运行时宠物窗口一致：正方形，避免 Canvas 默认竖长把键盘挤没、圆角裁切异常。
        .frame(width: side, height: side)
}
