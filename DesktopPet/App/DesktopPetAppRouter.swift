//
// DesktopPetAppRouter.swift
// 应用级路由：收敛浮层展示入口，由 AppCoordinator 持有。
//

import AppKit
import SwiftUI

@MainActor
final class DesktopPetAppRouter {
    let overlay: any OverlayPresenting

    init(overlay: any OverlayPresenting) {
        self.overlay = overlay
    }

    func attachPetWindow(_ window: NSWindow?) {
        overlay.attachPetWindow(window)
    }

    func toggleCarePanel(root: AnyView) {
        overlay.toggleCarePanel(root: root)
    }

    func toggleChatPanel(root: AnyView) {
        overlay.toggleChatPanel(root: root)
    }

    func presentChatPanel(root: AnyView) {
        overlay.presentChatPanel(root: root)
    }

    func dismissChatPanel() {
        overlay.dismissChatPanel()
    }

    func presentAgentSettings(root: AnyView) {
        overlay.presentAgentSettings(root: root)
    }

    func repositionOverlaysIfNeeded() {
        overlay.repositionIfNeeded()
    }

    func showTriggerBubble(text: String, onContinueChat: (() -> Void)? = nil) {
        overlay.showTriggerBubble(text: text, onContinueChat: onContinueChat)
    }

    func dismissTriggerBubble() {
        overlay.dismissTriggerBubble()
    }

    func isChatVisible() -> Bool {
        overlay.isChatVisible()
    }

    func isCareVisible() -> Bool {
        overlay.isCareVisible()
    }
}
