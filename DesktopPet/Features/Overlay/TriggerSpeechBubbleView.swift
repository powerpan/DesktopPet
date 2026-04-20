//
// TriggerSpeechBubbleView.swift
// 条件触发时小猫旁白：云朵气泡样式；尾巴可贴四边并沿边偏移以指向猫猫。
//

import AppKit
import CoreText
import SwiftUI

/// 尾巴贴在气泡的哪一侧（指向猫猫的一侧）。
enum TriggerBubbleTailEdge: Int, CaseIterable, Equatable, Sendable {
    case top
    case bottom
    case left
    case right
}

struct TriggerSpeechBubbleView: View {
    let text: String
    /// 与设置里「条件旁白气泡字体」倍数一致（与宠物窗口缩放独立）；**1.0** 为系统 callout 基准，与此前未单独调字体时一致。
    var bubbleFontScale: Double = 1.0
    var tailEdge: TriggerBubbleTailEdge = .bottom
    /// 沿附着边方向的偏移（pt）：上/下边为水平偏移（相对气泡宽度中心），左/右边为垂直偏移（相对高度中心）。
    var tailAlongOffset: CGFloat = 0
    /// 轻点气泡：通常先关气泡，再在回调里打开聊天等（由外层 `ExtensionOverlayController` 编排）。
    var onTap: () -> Void = {}

    private let textMaxWidthBase: CGFloat = 300
    private let tailW: CGFloat = 16
    private let tailH: CGFloat = 8

    private var textSizeMultiplier: CGFloat {
        CGFloat(PetConfig.clampedTriggerBubbleFontScale(bubbleFontScale))
    }

    /// 略放宽换行宽，避免放大字号后过早折行。
    private var textMaxWidth: CGFloat {
        min(320, textMaxWidthBase + 24 * max(0, textSizeMultiplier - 1))
    }

    private var bodyFontSize: CGFloat {
        NSFont.preferredFont(forTextStyle: .callout, options: [:]).pointSize * textSizeMultiplier
    }

    private var scrollMaxHeight: CGFloat {
        min(280, 220 * textSizeMultiplier)
    }

    private var useScroll: Bool {
        text.count > 200 || text.components(separatedBy: .newlines).count > 6
    }

    var body: some View {
        chrome
            .background(Color.clear)
            // 勿对整棵 chrome 使用 `drawingGroup`：`NSHostingView.fittingSize` 会明显偏大，
            // 面板右/下多出透明区，表现为文字右侧空、尾巴离宠窗远。
            .compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var chrome: some View {
        switch tailEdge {
        case .bottom:
            VStack(spacing: 0) {
                bubbleBody
                tailDown
                    .frame(width: tailW, height: tailH)
                    // SwiftUI 向下为正；负值会把三角整体上移、离宠窗更远。
                    .offset(x: tailAlongOffset, y: 2)
            }
        case .top:
            VStack(spacing: 0) {
                tailUp
                    .frame(width: tailW, height: tailH)
                    .offset(x: tailAlongOffset, y: 1)
                bubbleBody
            }
        case .right:
            HStack(spacing: 0) {
                bubbleBody
                tailRight
                    .frame(width: tailH, height: tailW)
                    .offset(x: -0.5, y: tailAlongOffset)
            }
        case .left:
            HStack(spacing: 0) {
                tailLeft
                    .frame(width: tailH, height: tailW)
                    .offset(x: 0.5, y: tailAlongOffset)
                bubbleBody
            }
        }
    }

    private var bubbleBody: some View {
        Group {
            if useScroll {
                ScrollView {
                    textBlock
                }
                .frame(maxHeight: scrollMaxHeight)
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

    /// 用 CoreText 在 `textMaxWidth` 下排版，取各行 `useGlyphPathBounds` 宽度最大值，与 SwiftUI 换行更一致且末行可收紧。
    private var fittedTextWidth: CGFloat {
        let sizingText = InlineMarkdownBubble.plainForSizing(text)
        guard !sizingText.isEmpty else { return 1 }
        let font = NSFont.systemFont(ofSize: bodyFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let attrString = NSAttributedString(string: sizingText, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: textMaxWidth, height: 200_000),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attrString.length),
            path,
            nil
        )
        let linesCF = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(linesCF)
        guard lineCount > 0 else { return 1 }
        var maxLine: CGFloat = 1
        for i in 0 ..< lineCount {
            let line = unsafeBitCast(CFArrayGetValueAtIndex(linesCF, i), to: CTLine.self)
            let b = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            maxLine = max(maxLine, ceil(b.width))
        }
        return min(textMaxWidth, maxLine)
    }

    private var textBlock: some View {
        Text(InlineMarkdownBubble.attributedDisplayString(text))
            .font(.system(size: bodyFontSize))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(width: fittedTextWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var tailDown: some View {
        TailShapeDown()
            .fill(.ultraThinMaterial)
            .overlay {
                TailShapeDown()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private var tailUp: some View {
        TailShapeUp()
            .fill(.ultraThinMaterial)
            .overlay {
                TailShapeUp()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private var tailRight: some View {
        TailShapeRight()
            .fill(.ultraThinMaterial)
            .overlay {
                TailShapeRight()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private var tailLeft: some View {
        TailShapeLeft()
            .fill(.ultraThinMaterial)
            .overlay {
                TailShapeLeft()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }
}

/// 顶点朝下（指向下方猫猫）
private struct TailShapeDown: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// 顶点朝上
private struct TailShapeUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 顶点朝右（指向右侧猫猫）
private struct TailShapeRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 顶点朝左
private struct TailShapeLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
