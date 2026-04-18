//
// PetSpriteView.swift
// 宠物画面占位：根据状态机显示大字状态标题（后续可换成精灵图或动画视图）。
//

import SwiftUI

struct PetSpriteView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var stateMachine: PetStateMachine
    @EnvironmentObject private var deskMirror: DeskMirrorModel

    /// 与 `petScale == 1.0` 时的布局边长一致，用于字号/圆角比例。
    private var layoutReferenceSide: CGFloat {
        PetConfig.petCanvasLayoutPoints * PetConfig.visualBaselineFactor
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(1, min(geo.size.width, geo.size.height))
            let u = side / layoutReferenceSide
            let cornerRadius = min(side * 0.12, max(4, side * 0.5 - 1))

            VStack(spacing: 6 * u) {
                Text("猫猫桌前（文字）")
                    .font(.system(size: max(8, 11 * u), weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)

                DeskMirrorTextView()

                Text(PetAnimationDriver.title(for: stateMachine.state))
                    .font(.system(size: max(12, 22 * u), weight: .bold, design: .rounded))
                    .accessibilityLabel(PetAnimationDriver.accessibilityLabel(for: stateMachine.state))

                Text(stateMachine.state.rawValue)
                    .font(.system(size: max(8, 11 * u), design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4 * u)
            .padding(.vertical, 3 * u)
            .environment(\.petCardContentScale, u)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .allowsHitTesting(!settings.isClickThroughEnabled)
        }
    }
}

// MARK: - 卡片内子视图字号比例（键盘镜像等）

private struct PetCardContentScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// 相对「滑条 1.0 × visualBaseline」布局边长的比例；用于 `DeskMirrorTextView` 等随缩放调字号与间距。
    var petCardContentScale: CGFloat {
        get { self[PetCardContentScaleKey.self] }
        set { self[PetCardContentScaleKey.self] = newValue }
    }
}
