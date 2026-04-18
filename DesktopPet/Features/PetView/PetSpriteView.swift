//
// PetSpriteView.swift
// 宠物画面占位：根据状态机显示大字状态标题（后续可换成精灵图或动画视图）。
//

import SwiftUI

struct PetSpriteView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var stateMachine: PetStateMachine
    @EnvironmentObject private var pointer: PointerTrackingModel

    var body: some View {
        VStack(spacing: 10) {
            Text(PetAnimationDriver.title(for: stateMachine.state))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .accessibilityLabel(PetAnimationDriver.accessibilityLabel(for: stateMachine.state))

            Text(stateMachine.state.rawValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .offset(x: pointer.gazeOffsetX)
        .animation(.easeOut(duration: 0.12), value: pointer.gazeOffsetX)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        // 鼠标穿透开启时：精灵区不接收点击，事件交给 AppKit 根视图的 hitTest 落到下层应用；仅右上角按钮仍可点。
        .allowsHitTesting(!settings.isClickThroughEnabled)
    }
}

