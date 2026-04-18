//
// ChatOverlayView.swift
// 智能体对话叠加层（DeepSeek）。
//

import Combine
import SwiftUI

struct ChatOverlayView: View {
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var agentSettings: AgentSettingsStore
    @EnvironmentObject private var deskMirror: DeskMirrorModel
    private let client = AgentClient()

    @State private var draft: String = ""
    @State private var keychainConfigured: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("七七猫 · 对话")
                    .font(.headline)
                Text(keychainConfigured ? "钥匙串：已检测到 API Key" : "钥匙串：未检测到 API Key（请在智能体设置中保存）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.messages) { m in
                            bubble(m)
                                .id(m.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: session.messages.count) { _, _ in
                    if let last = session.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let err = session.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
            }

            HStack(spacing: 8) {
                TextField("说点什么…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await send() } }
                Button(session.isSending ? "…" : "发送") {
                    Task { await send() }
                }
                .disabled(session.isSending)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            keychainConfigured = KeychainStore.readAPIKey() != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .desktopPetAPIKeyDidChange)) { _ in
            keychainConfigured = KeychainStore.readAPIKey() != nil
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 24) }
            Text(m.content)
                .font(.callout)
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            if !isUser { Spacer(minLength: 24) }
        }
    }

    @MainActor
    private func send() async {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        session.appendUser(t)
        session.setSending(true)
        session.lastError = nil
        let key = KeychainStore.readAPIKey()

        var systemPrompt = agentSettings.systemPrompt
        if agentSettings.attachKeySummary {
            let s = deskMirror.recentKeyLabelsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                systemPrompt += "\n\n（可选上下文）用户近期键入标签摘要：\(s.prefix(200))"
            }
        }

        let apiMessages: [[String: String]] = session.messages.compactMap { m in
            if m.role == "user" || m.role == "assistant" {
                return ["role": m.role, "content": m.content]
            }
            return nil
        }

        do {
            let reply = try await client.completeChat(
                baseURL: agentSettings.baseURL,
                model: agentSettings.model,
                apiKey: key,
                systemPrompt: systemPrompt,
                messages: apiMessages,
                temperature: agentSettings.temperature,
                maxTokens: agentSettings.maxTokens
            )
            session.appendAssistant(reply)
        } catch {
            session.lastError = error.localizedDescription
        }
        session.setSending(false)
    }
}
