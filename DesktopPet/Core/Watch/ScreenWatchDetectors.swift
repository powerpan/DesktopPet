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
    /// 在归一化矩形内比较左侧 1/3 与右侧 1/3 平均亮度差；差值大于阈值认为「右侧更亮」（常见于进度条走完）。
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
        guard outer.width >= 6, outer.height >= 6 else { return false }
        let thirdW = outer.width / 3
        let left = CGRect(x: outer.minX, y: outer.minY, width: thirdW, height: outer.height)
        let right = CGRect(x: outer.maxX - thirdW, y: outer.minY, width: thirdW, height: outer.height)
        guard let cgL = cg.cropping(to: left), let cgR = cg.cropping(to: right) else { return false }
        let l = averageLuminance(cgImage: cgL) ?? 0
        let r = averageLuminance(cgImage: cgR) ?? 0
        return (r - l) >= deltaThreshold
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
