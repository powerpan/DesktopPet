//
// OverlayPresenting.swift
// 浮层宿主协议：与具体 NSPanel/NSWindow 实现解耦，便于测试与替换。
//

import AppKit
import SwiftUI

@MainActor
protocol OverlayPresenting: AnyObject {
    func attachPetWindow(_ window: NSWindow?)
    func isCareVisible() -> Bool
    func isChatVisible() -> Bool
    func dismissChatPanel()
    func toggleCarePanel(root: AnyView)
    func toggleChatPanel(root: AnyView)
    func presentChatPanel(root: AnyView)
    func presentAgentSettings(root: AnyView)
    func repositionIfNeeded()
    func showTriggerBubble(text: String, onContinueChat: (() -> Void)?)
    func dismissTriggerBubble()
}

extension ExtensionOverlayController: OverlayPresenting {}
