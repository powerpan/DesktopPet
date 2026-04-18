//
// AccessibilityPermissionManager.swift
// 封装 AXIsProcessTrusted：查询与刷新「辅助功能」信任状态；全局键盘监听依赖此项为 true。
//

import ApplicationServices
import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    /// 用户点击「重新检测」或等价操作时，由界面发出，由 `AppCoordinator` 统一刷新信任并重启键盘监听。
    static let desktopPetAccessibilityRecheck = Notification.Name("desktopPetAccessibilityRecheck")
}

@MainActor
final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isGranted: Bool
    /// 每次检测后更新，便于用户确认「系统到底有没有认当前进程」
    @Published private(set) var lastRecheckSummary: String = ""
    /// 即使 `isGranted` 未变，也可让 SwiftUI 刷新诊断文案
    @Published private(set) var recheckToken: Int = 0

    init() {
        // 启动时不弹系统授权框，仅读取当前状态
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        isGranted = AXIsProcessTrustedWithOptions(options)
        rebuildSummary(granted: isGranted)
    }

    func refreshStatus(prompt: Bool = false, bumpUI: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        rebuildSummary(granted: granted)

        if bumpUI {
            recheckToken += 1
        }

        if bumpUI || granted != isGranted {
            isGranted = granted
        }
    }

    /// 用户点击「打开系统设置」等场景：允许系统弹出授权引导
    func requestIfNeeded() {
        refreshStatus(prompt: true, bumpUI: true)
    }

    private func rebuildSummary(granted: Bool) {
        let bid = Bundle.main.bundleIdentifier ?? "(无 bundle id)"
        let exec = (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String) ?? "(未知可执行名)"
        let path = Bundle.main.bundleURL.path
        lastRecheckSummary = """
        检测结果：\(granted ? "系统已信任本进程（可注册全局键盘）" : "系统仍未信任本进程")
        Bundle ID：\(bid)
        可执行名：\(exec)（辅助功能列表里应对应这一项）
        应用路径：\(path)

        若你已在设置里勾选但仍显示未信任：请完全退出 DesktopPet（菜单栏退出），再从 Xcode 重新 Run；Xcode 调试每次构建路径可能变化，需在「辅助功能」里勾选当前正在运行的那一条。
        """
    }
}
