//
// PetSpriteView.swift
// 宠物卡片：桌镜叠层为主（状态动画占位可后续接 GIF/序列帧）。
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
            // 左侧略留边、右侧更贴边（右上角设置叠在 overlay 上）；桌镜宽度与内边距一致避免右侧空带。
            let padLeading = max(2, 1.25 * u)
            let padTrailing = max(1, 0.35 * u)
            let deskMirrorLayoutWidth = max(28, side - padLeading - padTrailing)

            VStack(alignment: .leading, spacing: max(3, 5 * u)) {
                Text("七七猫2.0")
                    .font(.system(size: max(8, 11 * u), weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DeskMirrorTextView()
                    .layoutPriority(1)

                Text(stateMachine.state.rawValue)
                    .font(.system(size: max(5, 6.5 * u), design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, max(2, 2.5 * u))
            }
            .padding(.leading, padLeading)
            .padding(.trailing, padTrailing)
            .padding(.vertical, 3 * u)
            .environment(\.petCardContentScale, u)
            .environment(\.petCardLayoutInnerWidth, deskMirrorLayoutWidth)
            // 明确正方形 + 顶部对齐：不要用 maxHeight .infinity 撑满竖向，否则子视图会被挤到可视区外，底部圆角像「缺一块」。
            .frame(width: side, height: side, alignment: .top)
            .desktopPetPanelLiquidGlass(
                cornerRadius: cornerRadius,
                liquidGlassEnabled: settings.isLiquidGlassChromeEnabled,
                glassVariant: settings.liquidGlassVariant
            )
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

    /// `DeskMirrorTextView` 内整幅叠层可用宽度（已扣较窄水平 padding 与圆角/按钮余量）。
    var petCardLayoutInnerWidth: CGFloat {
        get { self[PetCardLayoutInnerWidthKey.self] }
        set { self[PetCardLayoutInnerWidthKey.self] = newValue }
    }
}
