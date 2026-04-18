//
// AgentSessionStore.swift
// 当前会话消息（内存）；清空策略由 UI 触发。
//

import Foundation
import SwiftUI

@MainActor
final class AgentSessionStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isSending = false
    @Published var lastError: String?

    func clearSession() {
        messages = []
        lastError = nil
    }

    func appendUser(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(ChatMessage(role: "user", content: t))
    }

    func appendAssistant(_ text: String) {
        messages.append(ChatMessage(role: "assistant", content: text))
    }

    func appendSystemNotice(_ text: String) {
        messages.append(ChatMessage(role: "system", content: text))
    }

    func setSending(_ v: Bool) {
        isSending = v
    }
}
