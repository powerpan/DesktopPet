//
// ScreenWatchDetectors.swift
// 盯屏：OCR 关键字 + 进度条区域亮度启发式。
//

import AppKit
import CoreGraphics
import Foundation
import Vision

enum ScreenWatchOCRDetector {
    /// 对整幅截图做 OCR，检查是否包含子串。
    static func imageContains(jpegData: Data, substring: String, caseInsensitive: Bool) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let img = NSImage(data: jpegData),
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    cont.resume(returning: false)
                    return
                }
                let request = VNRecognizeTextRequest { request, _ in
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let hay = lines.joined(separator: "\n")
                    let ok: Bool
                    if caseInsensitive {
                        ok = hay.range(of: substring, options: .caseInsensitive) != nil
                    } else {
                        ok = hay.contains(substring)
                    }
                    cont.resume(returning: ok)
                }
                request.recognitionLevel = .accurate
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }
}

enum ScreenWatchProgressHeuristic {
    /// 在归一化矩形内比较**左 1/5** 与**右 1/5** 的平均亮度（Rec.709，约 0=黑…1=白）。
    /// 典型「从左往右填满」的进度条：未完成时常一侧更亮、一侧更暗，**左右平均亮度差较大**；走完后整条常为同一颜色，**差值接近 0**。
    /// 当 `|右侧平均 − 左侧平均| <= deltaThreshold` 时返回 true。`deltaThreshold` 表示**允许的最大亮度差**（如 0.08 ≈ 8 个百分点）。
    /// 局限：若 0% 时轨条左右也已经很均匀，单靠本规则无法区分「未开始」与「已满」，请配合 OCR 或模型兜底。
    static func progressLikelyFilled(jpegData: Data, rect: NormalizedRect, deltaThreshold: Double) -> Bool {
        guard let img = NSImage(data: jpegData),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return false }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let outer = CGRect(
            x: rect.x * Double(w),
            y: rect.y * Double(h),
            width: rect.width * Double(w),
            height: rect.height * Double(h)
        ).integral
        guard outer.width >= 10, outer.height >= 6 else { return false }
        let fifthW = outer.width / 5
        guard fifthW >= 1 else { return false }
        let left = CGRect(x: outer.minX, y: outer.minY, width: fifthW, height: outer.height)
        let right = CGRect(x: outer.maxX - fifthW, y: outer.minY, width: fifthW, height: outer.height)
        guard let cgL = cg.cropping(to: left), let cgR = cg.cropping(to: right) else { return false }
        let l = averageLuminance(cgImage: cgL) ?? 0
        let r = averageLuminance(cgImage: cgR) ?? 0
        let cap = max(0, min(1, deltaThreshold))
        return abs(r - l) <= cap
    }

    private static func averageLuminance(cgImage: CGImage) -> Double? {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        let bitsPerComponent = 8
        var raw = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(
            data: &raw,
            width: w,
            height: h,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        var n = 0
        for y in 0 ..< h {
            for x in 0 ..< w {
                let o = y * bytesPerRow + x * bytesPerPixel
                let b = Double(raw[o]) / 255
                let g = Double(raw[o + 1]) / 255
                let r = Double(raw[o + 2]) / 255
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sum += lum
                n += 1
            }
        }
        guard n > 0 else { return nil }
        return sum / Double(n)
    }
}
