//
// ChatMultimodalAttachmentCodec.swift
// 本地 / 持久化附件 → OpenAI 兼容 `content` 片段；大小与类型校验。
//

import AppKit
import Foundation
import PDFKit

enum MultimodalAttachmentError: LocalizedError {
    case imageTooLarge(byteSize: Int, limit: Int)
    case fileTooLarge(byteSize: Int, limit: Int)
    case unreadableText(filename: String)
    case unsupportedKind(filename: String, mime: String)
    case invalidImage(filename: String)

    var errorDescription: String? {
        switch self {
        case let .imageTooLarge(byteSize, limit):
            return "图片过大（\(byteSize / 1024) KB），当前上限 \(limit / 1024) KB。请在「集成」调高「单张图片」限额。"
        case let .fileTooLarge(byteSize, limit):
            return "文件过大（\(byteSize / 1024) KB），当前上限 \(limit / 1024) KB。请在「集成」调高「单个文件」限额。"
        case let .unreadableText(name):
            return "无法以 UTF-8/UTF-16 读取文本文件：\(name)"
        case let .unsupportedKind(name, mime):
            return "暂不支持的附件类型：\(name)（\(mime)）。请使用图片，或 PDF / 纯文本类文件。"
        case let .invalidImage(name):
            return "无法解析为图片：\(name)"
        }
    }
}

enum ChatMultimodalAttachmentCodec {
    /// 用户从对话面板新选文件后编码（写入磁盘前校验）。
    static func partsFromLocalUpload(
        data: Data,
        filename: String,
        limits: MultimodalAttachmentLimitsStore
    ) throws -> [AgentAPIChatContentPart] {
        try partsFromData(data: data, filename: filename, limits: limits)
    }

    /// 从已落盘的附件再编码（发送前按**当前**限额复验）。
    static func partsFromPersistedRef(
        data: Data,
        ref: ChatAttachmentRef,
        limits: MultimodalAttachmentLimitsStore
    ) throws -> [AgentAPIChatContentPart] {
        try partsFromData(data: data, filename: ref.filename, limits: limits)
    }

    private static func partsFromData(
        data: Data,
        filename: String,
        limits: MultimodalAttachmentLimitsStore
    ) throws -> [AgentAPIChatContentPart] {
        let mime = mimeGuess(filename: filename, data: data)
        if mime.hasPrefix("image/") || looksLikeImage(filename: filename) {
            if data.count > limits.maxImageAttachmentBytes {
                throw MultimodalAttachmentError.imageTooLarge(byteSize: data.count, limit: limits.maxImageAttachmentBytes)
            }
            let (outData, outMime) = try normalizeImageForAPI(data: data, filename: filename, limits: limits)
            return [.imageData(mimeType: outMime, data: outData)]
        }

        if data.count > limits.maxFileAttachmentBytes {
            throw MultimodalAttachmentError.fileTooLarge(byteSize: data.count, limit: limits.maxFileAttachmentBytes)
        }

        let lower = filename.lowercased()
        if mime == "application/pdf" || lower.hasSuffix(".pdf") {
            let txt = try extractPDFText(data: data, maxUtf8Bytes: limits.maxTextExtractBytes)
            return [.text("【附件 PDF \(filename) 提取正文】\n" + txt)]
        }

        if mime.hasPrefix("text/")
            || ["json", "md", "markdown", "csv", "txt", "xml", "yaml", "yml", "log"].contains((filename as NSString).pathExtension.lowercased()) {
            guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw MultimodalAttachmentError.unreadableText(filename: filename)
            }
            let clipped = clipString(s, maxUtf8Bytes: limits.maxTextExtractBytes)
            return [.text("【附件 \(filename)】\n" + clipped)]
        }

        throw MultimodalAttachmentError.unsupportedKind(filename: filename, mime: mime)
    }

    private static func looksLikeImage(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"].contains(ext)
    }

    /// 供 UI 展示等使用。
    static func declaredMime(filename: String, data: Data) -> String {
        mimeGuess(filename: filename, data: data)
    }

    private static func mimeGuess(filename: String, data: Data) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt", "log": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "xml": return "application/xml"
        default: break
        }
        if data.count >= 3, data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF { return "image/jpeg" }
        if data.count >= 4, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 { return "image/png" }
        if data.count >= 3, data[0] == 0x47, data[1] == 0x49, data[2] == 0x46 { return "image/gif" }
        if data.count >= 4, data[0] == 0x25, data[1] == 0x50, data[2] == 0x44, data[3] == 0x46 { return "application/pdf" }
        return "application/octet-stream"
    }

    private static func normalizeImageForAPI(
        data: Data,
        filename: String,
        limits: MultimodalAttachmentLimitsStore
    ) throws -> (Data, String) {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "gif" || mimeGuess(filename: filename, data: data) == "image/gif" {
            return (data, "image/gif")
        }
        if ext == "png" && mimeGuess(filename: filename, data: data) == "image/png" {
            if data.count <= limits.maxImageAttachmentBytes { return (data, "image/png") }
        }

        guard let img = NSImage(data: data) else {
            throw MultimodalAttachmentError.invalidImage(filename: filename)
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw MultimodalAttachmentError.invalidImage(filename: filename)
        }
        var factor = 0.9
        var jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: factor])
        while let j = jpeg, j.count > limits.maxImageAttachmentBytes, factor > 0.35 {
            factor -= 0.08
            jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: factor])
        }
        guard let final = jpeg, !final.isEmpty else {
            throw MultimodalAttachmentError.invalidImage(filename: filename)
        }
        if final.count > limits.maxImageAttachmentBytes {
            throw MultimodalAttachmentError.imageTooLarge(byteSize: final.count, limit: limits.maxImageAttachmentBytes)
        }
        return (final, "image/jpeg")
    }

    private static func extractPDFText(data: Data, maxUtf8Bytes: Int) throws -> String {
        guard let doc = PDFDocument(data: data) else {
            return "（无法打开 PDF）"
        }
        var out = ""
        for i in 0 ..< doc.pageCount {
            guard let page = doc.page(at: i), let s = page.string else { continue }
            out += s + "\n\n"
            if out.utf8.count >= maxUtf8Bytes { break }
        }
        return clipString(out, maxUtf8Bytes: maxUtf8Bytes)
    }

    private static func clipString(_ s: String, maxUtf8Bytes: Int) -> String {
        if s.utf8.count <= maxUtf8Bytes { return s }
        var out = ""
        for ch in s {
            let piece = String(ch)
            if out.utf8.count + piece.utf8.count > maxUtf8Bytes { break }
            out.append(contentsOf: piece)
        }
        return out + "\n\n…（正文过长，已按「集成」中的文本抽取上限截断）"
    }
}
