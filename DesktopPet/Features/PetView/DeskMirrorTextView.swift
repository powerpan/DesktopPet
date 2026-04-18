//
// DeskMirrorTextView.swift
// 桌前镜像：底图 + 同画布尺寸的爪印 / 鼠标方向叠层（与 BongoCat keyboard/resources 一致），非小格贴图。
//

import AppKit
import SwiftUI

struct DeskMirrorTextView: View {
    @EnvironmentObject private var deskMirror: DeskMirrorModel
    @EnvironmentObject private var settings: SettingsViewModel
    @Environment(\.petCardContentScale) private var u
    @Environment(\.petCardLayoutInnerWidth) private var layoutW

    var body: some View {
        let w = max(1, layoutW)
        VStack(alignment: .leading, spacing: max(2, 1.75 * u)) {
            if !settings.isDeskKeyMirrorEnabled {
                Text("已在设置中关闭按键镜像")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !deskMirror.accessibilityKeyboardMirrorGranted {
                Text("需辅助功能权限以镜像按键")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                deskMirrorComposite(width: w)
                if !deskMirror.recentKeyLabelsSummary.isEmpty {
                    Text(deskMirror.recentKeyLabelsSummary)
                        .font(.system(size: max(6, 9 * u), design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.42)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, max(1, 0.9 * u))
                }
            }
        }
        .frame(width: w, alignment: .leading)
    }

    /// 与 cover 底图同范围、同比例：底图 + 全画布按键层 + 全画布鼠标层。
    private func deskMirrorComposite(width w: CGFloat) -> some View {
        let inputActive = deskMirror.presentationMouseDirection != .none || deskMirror.presentationHighlightedKeyCode != nil
        let aspect = DeskMirrorKeyImage.deskMirrorArtAspectRatio(inputActive: inputActive)
        return ZStack {
            if let bg = DeskMirrorKeyImage.deskMirrorCoverImage(inputActive: inputActive) {
                Image(nsImage: bg)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.12)
            }

            if let code = deskMirror.presentationHighlightedKeyCode,
               let paw = DeskMirrorKeyImage.leftKeyImage(forKeyCode: code) {
                Image(nsImage: paw)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }

            mouseFullCanvasOverlay()
        }
        .frame(width: w)
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: max(3, 4 * u), style: .continuous))
    }

    @ViewBuilder
    private func mouseFullCanvasOverlay() -> some View {
        switch deskMirror.presentationMouseDirection {
        case .none:
            Color.clear
        default:
            if let img = DeskMirrorKeyImage.mouseImage(for: deskMirror.presentationMouseDirection) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
                    .overlay {
                        mouseDirectionSFOnly()
                    }
            }
        }
    }

    /// PNG 缺失时在整幅区域中央画系统箭头（与旧逻辑一致）。
    private func mouseDirectionSFOnly() -> some View {
        let dir = deskMirror.presentationMouseDirection
        return GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) * 0.12
            Group {
                switch dir {
                case .none:
                    Image(systemName: "circle.dotted")
                        .font(.system(size: s, weight: .regular))
                        .foregroundStyle(.tertiary)
                case .up:
                    Image(systemName: "arrow.up")
                        .font(.system(size: s, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .down:
                    Image(systemName: "arrow.down")
                        .font(.system(size: s, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .left:
                    Image(systemName: "arrow.left")
                        .font(.system(size: s, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .right:
                    Image(systemName: "arrow.right")
                        .font(.system(size: s, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
