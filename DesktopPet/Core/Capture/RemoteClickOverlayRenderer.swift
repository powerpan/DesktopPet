//
// RemoteClickOverlayRenderer.swift
// 在截图 JPEG 上叠加 0–100 网格与刻度（用户坐标与图像左上原点一致）。
//

import AppKit
import CoreGraphics
import ImageIO
import Foundation

enum RemoteClickOverlayRenderer {
    /// 在 JPEG 数据上绘制标尺，返回新的 JPEG（失败则返回原数据）。
    static func renderOverlayOnJPEG(_ jpegData: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return jpegData }

        let w = cg.width
        let h = cg.height
        guard w > 2, h > 2 else { return jpegData }

        let img = NSImage(size: NSSize(width: w, height: h), flipped: true) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: bounds)

            let bw = bounds.width
            let bh = bounds.height
            let lineW = max(1, min(bw, bh) / 400)
            ctx.setLineWidth(lineW)

            for step in stride(from: 0, through: 100, by: 10) {
                let t = CGFloat(step) / 100
                let isMajor = step % 50 == 0
                let c = (isMajor ? NSColor.white.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.35)).cgColor
                ctx.setStrokeColor(c)
                let vx = t * bw
                let vy = t * bh
                ctx.move(to: CGPoint(x: vx, y: 0))
                ctx.addLine(to: CGPoint(x: vx, y: bh))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: 0, y: vy))
                ctx.addLine(to: CGPoint(x: bw, y: vy))
                ctx.strokePath()
            }

            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.stroke(CGRect(x: 0.5, y: 0.5, width: bw - 1, height: bh - 1))

            let fontSize = max(10, min(bw, bh) * 0.028)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = .zero
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .shadow: shadow,
            ]

            for step in stride(from: 0, through: 100, by: 10) {
                let t = CGFloat(step) / 100
                let label = "\(step)" as NSString
                let sz = label.size(withAttributes: attrs)
                label.draw(
                    at: CGPoint(x: t * bw - sz.width / 2, y: bh - sz.height - 2),
                    withAttributes: attrs
                )
                let ay = (1 - t) * bh - sz.height / 2
                label.draw(at: CGPoint(x: 2, y: ay), withAttributes: attrs)
            }

            ctx.restoreGState()
            return true
        }

        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let out = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            return jpegData
        }
        return out
    }
}
