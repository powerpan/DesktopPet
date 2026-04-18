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
            /// 水平 padding 后、再为 `PetContainerView` 右上角浮动按钮留出宽度，避免键盘/鼠标垫被裁切或叠在按钮下。
            let innerAfterHPadding = max(1, side - 8 * u)
            let deskMirrorLayoutWidth = max(44, innerAfterHPadding - (26 + 8 * u))

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
            .environment(\.petCardLayoutInnerWidth, deskMirrorLayoutWidth)
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

private struct PetCardLayoutInnerWidthKey: EnvironmentKey {
    /// 与 `PetSpriteView` 中传给 `DeskMirrorTextView` 的可用宽度一致；预览未注入时用保守默认。
    static let defaultValue: CGFloat = 104
}

extension EnvironmentValues {
    /// 相对「滑条 1.0 × visualBaseline」布局边长的比例；用于 `DeskMirrorTextView` 等随缩放调字号与间距。
    var petCardContentScale: CGFloat {
        get { self[PetCardContentScaleKey.self] }
        set { self[PetCardContentScaleKey.self] = newValue }
    }

    /// `DeskMirrorTextView` 内 HStack 可用总宽（已扣水平 padding 与右上角按钮占位）。
    var petCardLayoutInnerWidth: CGFloat {
        get { self[PetCardLayoutInnerWidthKey.self] }
        set { self[PetCardLayoutInnerWidthKey.self] = newValue }
    }
}
