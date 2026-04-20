//
// ScreenCaptureService.swift
// 主/副显示器单次截屏（ScreenCaptureKit）→ 缩放 → JPEG，仅内存、不落盘。
//

import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

enum ScreenCaptureServiceError: LocalizedError, Equatable {
    case permissionDenied
    case noDisplay
    case noSecondaryDisplay
    case invalidCaptureTarget
    case streamFailed(String)
    case noFrame
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未授予屏幕录制权限。请在「系统设置 → 隐私与安全性 → 屏幕录制」中勾选本应用。"
        case .noDisplay:
            return "未找到可用显示器。"
        case .noSecondaryDisplay:
            return "未检测到副显示器（仅有一块屏或系统未列出第二块）。"
        case .invalidCaptureTarget:
            return "截屏目标为「关」，无法截取。"
        case let .streamFailed(s):
            return "截屏流失败：\(s)"
        case .noFrame:
            return "截屏未收到画面帧（超时或已停止）。"
        case .encodingFailed:
            return "图像编码失败。"
        }
    }
}

/// 单次显示器截屏；不负责 prompt 或网络。
enum ScreenCaptureService {
    /// 是否已通过系统「屏幕录制」授权（不弹窗）。
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 请求系统屏幕录制权限（可能弹出系统对话框）。
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// 按总开关档位截取一帧（`.off` 会抛错）；缩放到 `maxEdge` 像素以内，输出 JPEG。
    static func captureJPEG(for target: ScreenSnapCaptureTarget, maxEdge: Int, jpegQuality: CGFloat) async throws -> Data {
        guard target != .off else {
            throw ScreenCaptureServiceError.invalidCaptureTarget
        }
        guard hasScreenRecordingPermission else {
            throw ScreenCaptureServiceError.permissionDenied
        }
        let q = min(0.95, max(0.4, jpegQuality))
        let edge = min(2048, max(256, maxEdge))
        let buffer = try await capturePixelBuffer(for: target, seconds: 8)
        return try jpegData(from: buffer, maxEdge: edge, quality: q)
    }

    /// 捕获主显示器一帧（兼容旧调用点）。
    static func captureMainDisplayJPEG(maxEdge: Int, jpegQuality: CGFloat) async throws -> Data {
        try await captureJPEG(for: .mainDisplay, maxEdge: maxEdge, jpegQuality: jpegQuality)
    }

    /// 与当前截取目标一致的 `CGDisplayBounds`（用于远程点屏坐标映射等）。
    static func displayBounds(for target: ScreenSnapCaptureTarget) async throws -> CGRect {
        guard target != .off else {
            throw ScreenCaptureServiceError.invalidCaptureTarget
        }
        let id = try await resolveCGDisplayID(for: target)
        return CGDisplayBounds(id)
    }

    // MARK: - SCK

    private static func resolveSCDisplay(for target: ScreenSnapCaptureTarget, content: SCShareableContent) throws -> SCDisplay {
        let mainID = CGMainDisplayID()
        switch target {
        case .off:
            throw ScreenCaptureServiceError.invalidCaptureTarget
        case .mainDisplay:
            guard let d = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
                throw ScreenCaptureServiceError.noDisplay
            }
            return d
        case .secondaryDisplay:
            let others = content.displays.filter { $0.displayID != mainID }.sorted { $0.displayID < $1.displayID }
            guard let d = others.first else {
                throw ScreenCaptureServiceError.noSecondaryDisplay
            }
            return d
        }
    }

    private static func resolveCGDisplayID(for target: ScreenSnapCaptureTarget) async throws -> CGDirectDisplayID {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let d = try resolveSCDisplay(for: target, content: content)
        return d.displayID
    }

    private static func capturePixelBuffer(for target: ScreenSnapCaptureTarget, seconds: TimeInterval) async throws -> CVPixelBuffer {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let display = try resolveSCDisplay(for: target, content: content)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA as OSType
        config.showsCursor = true
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let grabber = FrameGrabber()
        let stream = SCStream(filter: filter, configuration: config, delegate: grabber)
        grabber.stream = stream
        try stream.addStreamOutput(grabber, type: .screen, sampleHandlerQueue: grabber.queue)

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            grabber.onFirstFrame = { box.resume(with: $0) }

            Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    box.resume(with: .failure(ScreenCaptureServiceError.noFrame))
                } catch {}
            }

            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    box.resume(with: .failure(ScreenCaptureServiceError.streamFailed(error.localizedDescription)))
                }
            }
        }
    }

    // MARK: - Encode

    private static func jpegData(from pixelBuffer: CVPixelBuffer, maxEdge: Int, quality: CGFloat) throws -> Data {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { throw ScreenCaptureServiceError.encodingFailed }
        let w = extent.width
        let h = extent.height
        let scale = min(1, CGFloat(maxEdge) / max(w, h))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent.integral
        guard let cgImage = ctx.createCGImage(scaled, from: scaledExtent) else {
            throw ScreenCaptureServiceError.encodingFailed
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw ScreenCaptureServiceError.encodingFailed
        }
        return data
    }
}

// MARK: - Continuation (single resume)

private final class ContinuationBox {
    private var hasResumed = false
    private let lock = NSLock()
    private let continuation: CheckedContinuation<CVPixelBuffer, Error>

    init(_ continuation: CheckedContinuation<CVPixelBuffer, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<CVPixelBuffer, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(with: result)
    }
}

// MARK: - Stream output

private final class FrameGrabber: NSObject, SCStreamOutput, SCStreamDelegate {
    weak var stream: SCStream?
    let queue = DispatchQueue(label: "DesktopPet.ScreenCaptureKit.FrameGrabber")
    var onFirstFrame: ((Result<CVPixelBuffer, Error>) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFirstFrame?(.success(pb))
        onFirstFrame = nil
        Task { try? await stream.stopCapture() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error?) {
        if let error {
            onFirstFrame?(.failure(ScreenCaptureServiceError.streamFailed(error.localizedDescription)))
        }
        onFirstFrame = nil
    }
}
