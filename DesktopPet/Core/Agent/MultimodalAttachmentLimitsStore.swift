//
// MultimodalAttachmentLimitsStore.swift
// 对话 / Slack 多模态附件大小上限（UserDefaults），在「集成」Tab 中调节。
//

import Foundation
import SwiftUI

/// 限额数值可在任意线程读取；UI 绑定仍在主线程更新即可。
final class MultimodalAttachmentLimitsStore: ObservableObject {
    private enum Keys {
        static let maxImage = "DesktopPet.multimodal.maxImageAttachmentBytes.v1"
        static let maxFile = "DesktopPet.multimodal.maxFileAttachmentBytes.v1"
        static let maxTextExtract = "DesktopPet.multimodal.maxTextExtractBytes.v1"
    }

    /// 单张图片（JPEG/PNG/GIF 等）最大字节数。
    @Published var maxImageAttachmentBytes: Int {
        didSet { persist() }
    }

    /// 单个非图片文件（提取文本前）最大字节数。
    @Published var maxFileAttachmentBytes: Int {
        didSet { persist() }
    }

    /// PDF / 纯文本等抽取后注入模型的最大字符 UTF-8 字节数。
    @Published var maxTextExtractBytes: Int {
        didSet { persist() }
    }

    private let defaults = UserDefaults.standard

    init() {
        let defImg = 8 * 1024 * 1024
        let defFile = 3 * 1024 * 1024
        let defTxt = 200_000
        maxImageAttachmentBytes = max(
            Self.minImageBytes,
            min(Self.maxImageBytesCap, defaults.object(forKey: Keys.maxImage) as? Int ?? defImg)
        )
        maxFileAttachmentBytes = max(
            Self.minFileBytes,
            min(Self.maxFileBytesCap, defaults.object(forKey: Keys.maxFile) as? Int ?? defFile)
        )
        maxTextExtractBytes = max(
            Self.minTextExtractBytes,
            min(Self.maxTextExtractCap, defaults.object(forKey: Keys.maxTextExtract) as? Int ?? defTxt)
        )
    }

    static let minImageBytes = 512 * 1024
    static let maxImageBytesCap = 25 * 1024 * 1024
    static let minFileBytes = 1024
    static let maxFileBytesCap = 20 * 1024 * 1024
    static let minTextExtractBytes = 4096
    static let maxTextExtractCap = 2 * 1024 * 1024

    func clampAll() {
        maxImageAttachmentBytes = clamp(maxImageAttachmentBytes, min: Self.minImageBytes, max: Self.maxImageBytesCap)
        maxFileAttachmentBytes = clamp(maxFileAttachmentBytes, min: Self.minFileBytes, max: Self.maxFileBytesCap)
        maxTextExtractBytes = clamp(maxTextExtractBytes, min: Self.minTextExtractBytes, max: Self.maxTextExtractCap)
    }

    private func persist() {
        defaults.set(maxImageAttachmentBytes, forKey: Keys.maxImage)
        defaults.set(maxFileAttachmentBytes, forKey: Keys.maxFile)
        defaults.set(maxTextExtractBytes, forKey: Keys.maxTextExtract)
    }

    private func clamp(_ v: Int, min: Int, max: Int) -> Int {
        Swift.min(max, Swift.max(min, v))
    }
}
