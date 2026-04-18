//
// TriggerSpeechBubbleView.swift
// 条件触发时小猫旁白：云朵气泡样式，轻点关闭。
//

import SwiftUI

struct TriggerSpeechBubbleView: View {
    let text: String
    var onTapDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)

            BubbleTailShape()
                .fill(.ultraThinMaterial)
                .frame(width: 16, height: 8)
                .overlay {
                    BubbleTailShape()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
                .offset(y: -0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: 280)
        .contentShape(Rectangle())
        .onTapGesture { onTapDismiss() }
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
