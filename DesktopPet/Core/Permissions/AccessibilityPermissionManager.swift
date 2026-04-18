//
// AccessibilityPermissionManager.swift
// 封装 AXIsProcessTrusted：查询与刷新「辅助功能」信任状态；全局键盘监听依赖此项为 true。
//

import ApplicationServices
import Combine
import Foundation
import SwiftUI

@MainActor
final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isGranted: Bool

    init() {
        // 启动时不弹系统授权框，仅读取当前状态
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        isGranted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshStatus(prompt: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        guard granted != isGranted else { return }
        isGranted = granted
    }

    /// 用户点击「打开系统设置」等场景：允许系统弹出授权引导
    func requestIfNeeded() {
        refreshStatus(prompt: true)
    }
}
