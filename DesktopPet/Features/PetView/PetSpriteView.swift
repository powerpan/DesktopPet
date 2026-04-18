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
            // 父视图可能非正方形（如 Xcode Preview）；始终以短边为边长做「正方形卡片」，避免竖长区域把键盘挤到底部、圆角与背景错位。
            let side = max(1, min(geo.size.width, geo.size.height))
            let u = side / layoutReferenceSide
            let cornerRadius = min(side * 0.12, max(4, side * 0.5 - 1))
            // 桌镜行用满水平内宽；右上角按钮叠在 overlay 上，不必再整体减 30+ pt 否则右侧会空一大块。
            let innerAfterHPadding = max(1, side - 8 * u)
            let deskMirrorLayoutWidth = max(28, innerAfterHPadding - 4)

            VStack(alignment: .leading, spacing: max(3, 5 * u)) {
                Text("猫猫桌前（文字）")
                    .font(.system(size: max(8, 11 * u), weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DeskMirrorTextView()
                    .layoutPriority(1)

                Text(PetAnimationDriver.title(for: stateMachine.state))
                    .font(.system(size: min(side * 0.2, max(11, 20 * u)), weight: .bold, design: .rounded))
                    .accessibilityLabel(PetAnimationDriver.accessibilityLabel(for: stateMachine.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(stateMachine.state.rawValue)
                    .font(.system(size: max(7, 10 * u), design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 4 * u)
            .padding(.vertical, 3 * u)
            .environment(\.petCardContentScale, u)
            .environment(\.petCardLayoutInnerWidth, deskMirrorLayoutWidth)
            // 明确正方形 + 顶部对齐：不要用 maxHeight .infinity 撑满竖向，否则子视图会被挤到可视区外，底部圆角像「缺一块」。
            .frame(width: side, height: side, alignment: .top)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(!settings.isClickThroughEnabled)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
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
