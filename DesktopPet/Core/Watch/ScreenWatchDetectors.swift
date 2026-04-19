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
                    // 合并每条识别的多个候选，降低「正确字形在 top-2」时的漏检；并显式包含中文，利于界面小字。
                    var chunks: [String] = []
                    chunks.reserveCapacity(observations.count * 4)
                    for obs in observations {
                        let cands = obs.topCandidates(6)
                        for c in cands {
                            let s = c.string.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !s.isEmpty { chunks.append(s) }
                        }
                    }
                    let hay = chunks.joined(separator: "\n")
                    let ok: Bool
                    if caseInsensitive {
                        ok = hay.range(of: substring, options: .caseInsensitive) != nil
                    } else {
                        ok = hay.contains(substring)
                    }
                    cont.resume(returning: ok)
                }
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
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
    /// 典型「从左往右填满」：未完成时常 **`|左−右|` 较大**；走完后整条颜色接近一致，**`|左−右|` 很小**。
    /// 为避免 0% 时整条底轨颜色已很均匀而误判为「已满」，需先观察到一次足够大的左右不对称（`armed = true`），
    /// 之后才在 **`|左−右| <= maxLuminanceDelta`** 时返回 true。若任务从接近 100% 才开始盯，可能一直无法武装，请用模型兜底或 OCR。
    static func progressLikelyFilled(
        jpegData: Data,
        rect: NormalizedRect,
        maxLuminanceDelta: Double,
        armed: inout Bool
    ) -> Bool {
        guard let (l, r) = leftRightFifthMeanLuminances(jpegData: jpegData, rect: rect) else { return false }
        let delta = abs(r - l)
        let cap = max(0, min(1, maxLuminanceDelta))
        // 至少出现一次「明显在走进度」的不对称，才接受后续的「够均匀」。
        let armNeed = min(0.45, max(0.12, cap + 0.08, cap * 2.0))
        if delta >= armNeed {
            armed = true
        }
        return armed && delta <= cap
    }

    private static func leftRightFifthMeanLuminances(jpegData: Data, rect: NormalizedRect) -> (Double, Double)? {
        guard let img = NSImage(data: jpegData),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let outer = CGRect(
            x: rect.x * Double(w),
            y: rect.y * Double(h),
            width: rect.width * Double(w),
            height: rect.height * Double(h)
        ).integral
        guard outer.width >= 10, outer.height >= 6 else { return nil }
        let fifthW = outer.width / 5
        guard fifthW >= 1 else { return nil }
        let left = CGRect(x: outer.minX, y: outer.minY, width: fifthW, height: outer.height)
        let right = CGRect(x: outer.maxX - fifthW, y: outer.minY, width: fifthW, height: outer.height)
        guard let cgL = cg.cropping(to: left), let cgR = cg.cropping(to: right) else { return nil }
        let l = averageLuminance(cgImage: cgL) ?? 0
        let r = averageLuminance(cgImage: cgR) ?? 0
        return (l, r)
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
