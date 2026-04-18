//
// TriggerSpeechBubbleView.swift
// 条件触发时小猫旁白：云朵气泡样式；轻点后由外层收起并可打开聊天续聊。
//

import SwiftUI

struct TriggerSpeechBubbleView: View {
    let text: String
    /// 轻点气泡：通常先关气泡，再在回调里打开聊天等（由外层 `ExtensionOverlayController` 编排）。
    var onTap: () -> Void = {}

    private let textMaxWidth: CGFloat = 300

    /// 较长旁白时使用滚动，避免占满屏幕。
    private var useScroll: Bool {
        text.count > 200 || text.components(separatedBy: .newlines).count > 6
    }

    var body: some View {
        VStack(spacing: 0) {
            bubbleBody
            BubbleTailShape()
                .fill(.ultraThinMaterial)
                .frame(width: 16, height: 8)
                .overlay {
                    BubbleTailShape()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
                .offset(y: -1)
        }
        .background(Color.clear)
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 9, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    /// 圆角底板与文字同一裁剪区域，避免描边/材质在圆角外露出直角感。
    private var bubbleBody: some View {
        Group {
            if useScroll {
                ScrollView {
                    textBlock
                }
                .frame(maxHeight: 220)
            } else {
                textBlock
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .inset(by: 0.5)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var textBlock: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: textMaxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 顶点朝下，指向猫猫
private struct BubbleTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
