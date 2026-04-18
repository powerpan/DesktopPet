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
    /// 钥匙串中的 DeepSeek API Key 已写入或清除，供对话面板等刷新「已配置」提示。
    static let desktopPetAPIKeyDidChange = Notification.Name("desktopPetAPIKeyDidChange")
    /// 从设置「历史会话」选择某频道继续聊天：`userInfo["channelId"]` 为频道 UUID 字符串。
    static let desktopPetPresentChatContinuingChannel = Notification.Name("desktopPetPresentChatContinuingChannel")
}

@MainActor
final class AccessibilityPermissionManager: ObservableObject {
    /// 在未授权期间是否已触发过一次「带 prompt 的 AX 检查」，用于促使系统将本应用写入「辅助功能」列表（见 `scheduleAccessibilityListingRegistrationPromptIfNeeded`）。授权成功后清零。
    private static let tccListingPromptUsedKey = "DesktopPetAccessibilityTCCListingPromptUsedUntilGrant"

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
        if isGranted {
            UserDefaults.standard.set(false, forKey: Self.tccListingPromptUsedKey)
        }
    }

    /// 用户点击「打开系统设置」等场景：允许系统弹出授权引导
    func requestIfNeeded() {
        refreshStatus(prompt: true, bumpUI: true)
    }

    /// 首次未授权启动时延迟触发一次 `prompt: true`，促使系统将本应用出现在「系统设置 → 辅助功能」列表中（用户若自行先打开设置则列表可能为空）。
    func scheduleAccessibilityListingRegistrationPromptIfNeeded() {
        guard !isGranted else { return }
        guard !UserDefaults.standard.bool(forKey: Self.tccListingPromptUsedKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            guard let self, !self.isGranted else { return }
            guard !UserDefaults.standard.bool(forKey: Self.tccListingPromptUsedKey) else { return }
            UserDefaults.standard.set(true, forKey: Self.tccListingPromptUsedKey)
            self.refreshStatus(prompt: true, bumpUI: true)
        }
    }

    /// 用户确认列表里仍没有本应用时，再次向系统登记（可能出现系统提示框）。
    func triggerAccessibilityTrustPromptForSystemListing() {
        refreshStatus(prompt: true, bumpUI: true)
    }

    private func rebuildSummary(granted: Bool) {
        let bid = Bundle.main.bundleIdentifier ?? "(无 bundle id)"
        let exec = (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String) ?? "(未知可执行名)"
        let path = Bundle.main.bundleURL.path
        let legacyAX = AXIsProcessTrusted()
        let tccSyncNote = granted
            ? ""
            : """

        刚在系统设置里打开开关后，**立刻**点「重新检测」仍可能暂时为 false：系统把权限同步到当前进程常需 **1～10 秒**（不是应用逻辑错误）。本应用会在约 **10 秒内自动多次再检测**；也可先 **点一下本权限窗口** 再点「重新检测」。若多轮后仍为 false，请核对是否只打开了**与上面「应用路径」一致**的那一项，且 Xcode 已选 **Signing Team**。
        """
        lastRecheckSummary = """
        检测结果：\(granted ? "系统已信任本进程（可注册全局键盘）" : "系统仍未信任本进程")
        AXIsProcessTrusted() = \(legacyAX)（应与上一行含义一致）\(tccSyncNote)
        Bundle ID：\(bid)
        可执行名：\(exec)（系统列表里名称/图标应对应当前运行的 .app）
        应用路径：\(path)

        若系统「辅助功能」列表里**根本没有** DesktopPet：通常是你还**没从本应用**触发过登记。请先回到本应用，在权限窗口点 **「打开系统设置」**（或 **「让我在列表中出现」**），或等待启动后约 1 秒内可能出现的系统提示；**不要**在未运行本应用时单独去设置里找。

        若列表里曾勾选过 com.example.DesktopPet 或其它旧路径：请打开「系统设置 → 隐私与安全性 → 辅助功能」，用「−」删掉所有旧的 DesktopPet 项，再退出本应用并从 Xcode 重新 Run，只勾选**当前路径**对应的一条。

        若开关**刚打开、离开本页再回来又变关**：不是本应用代码关的（App 无法从内部关掉系统设置里的开关）。常见情况：(1) 列表里有多条 DesktopPet，你打开的是 A，回来时滚动位置看到的是另一条 B（仍为关）；(2) 在此期间 Xcode **再次 Run / Build**，可执行文件签名变化，系统把它当成新条目，旧开关不再对应当前进程；(3) 企业管理/描述文件限制。请删掉重复项，只保留**与上面「应用路径」一致**的一条并打开；勾选后菜单栏 **退出** 本应用再启动一次，在权限窗口点 **重新检测** 确认。

        【最常见根因】Xcode 里 **Signing → Team 为空** 时，产物多为 ad-hoc，系统常表现为「列表里能勾，但 AXIsProcessTrusted 一直 false」。请先在终端自检（整行复制）：
        codesign -dvvv "\(path)" 2>&1 | /usr/bin/grep -E 'Authority|TeamIdentifier|adhoc'
        若输出里**没有** TeamIdentifier、或明确为 ad-hoc：在 **Target → Signing & Capabilities** 为你的 Apple ID 选择 **Team**（Personal Team 即可）→ **Product → Clean Build Folder** → 再 Run → 回到辅助功能里删掉旧 DesktopPet 项后**只勾当前这一条**。

        若仍显示未信任，可在「终端」执行下面命令清除该 Bundle 的辅助功能记录后，再重新 Run 并在设置里勾选一次：
        tccutil reset Accessibility \(bid)
        """
    }
}
