//
// ChatOverlayView.swift
// 智能体对话叠加层（DeepSeek）；多会话频道持久化，API 仅发送 user/assistant。
//

import SwiftUI

struct ChatOverlayView: View {
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var agentSettings: AgentSettingsStore
    @EnvironmentObject private var deskMirror: DeskMirrorModel
    private let client = AgentClient()

    @State private var draft: String = ""
    @State private var keychainConfigured: Bool = false
    @State private var showRenameAlert = false
    @State private var renameDraft: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("七七猫 · 对话")
                        .font(.headline)
                    Text(keychainConfigured ? "钥匙串：已检测到 API Key" : "钥匙串：未检测到 API Key（请在智能体设置中保存）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    channelToolbar
                    if let ch = session.activeChannel {
                        Text("当前：\(ch.title) · 更新 \(formatted(ch.updatedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("手动对话支持多会话频道（UserDefaults 持久化）。条件触发的旁白先入历史并以气泡展示；轻点气泡会新建会话带上文并打开本面板。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button {
                    NotificationCenter.default.post(name: .desktopPetCloseChatOverlay, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭对话窗口")
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
                    scrollToLast(proxy: proxy)
                }
                .onChange(of: session.activeChannelId) { _, _ in
                    scrollToLast(proxy: proxy)
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
            keychainConfigured = KeychainStore.readAPIKey(forProvider: agentSettings.activeAPIProvider) != nil
        }
        .onChange(of: agentSettings.activeAPIProvider) { _, _ in
            keychainConfigured = KeychainStore.readAPIKey(forProvider: agentSettings.activeAPIProvider) != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .desktopPetAPIKeyDidChange)) { _ in
            keychainConfigured = KeychainStore.readAPIKey(forProvider: agentSettings.activeAPIProvider) != nil
        }
        .alert("重命名当前会话", isPresented: $showRenameAlert) {
            TextField("标题", text: $renameDraft)
            Button("取消", role: .cancel) {}
            Button("确定") {
                session.renameChannel(id: session.activeChannelId, title: renameDraft)
            }
        } message: {
            Text("标题会写入本地并随应用重启保留。")
        }
        .confirmationDialog("删除当前会话？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                session.deleteChannel(id: session.activeChannelId)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除该频道及其消息；至少保留一个会话。")
        }
    }

    private var channelToolbar: some View {
        HStack(spacing: 8) {
            Picker("会话", selection: Binding(
                get: { session.activeChannelId },
                set: { session.selectChannel(id: $0) }
            )) {
                ForEach(session.channels) { ch in
                    Text(ch.title).tag(ch.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)

            Button {
                _ = session.createNewEmptyChannel()
            } label: {
                Image(systemName: "plus.message")
            }
            .help("新建会话")

            Button {
                renameDraft = session.activeChannel?.title ?? ""
                showRenameAlert = true
            } label: {
                Image(systemName: "pencil")
            }
            .help("重命名当前会话")

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .help("删除当前会话")
            .disabled(session.channels.count <= 1)
        }
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        if let last = session.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.role == "system" {
            Text(m.content)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            let isUser = m.role == "user"
            HStack {
                if isUser { Spacer(minLength: 24) }
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    if m.slackMessageTs != nil {
                        Text("Slack")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2), in: Capsule())
                    }
                    Text(InlineMarkdownBubble.attributedDisplayString(m.content))
                        .font(.callout)
                        .padding(10)
                        .background(isUser ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if !isUser { Spacer(minLength: 24) }
            }
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
        let key = KeychainStore.readAPIKey(forProvider: agentSettings.activeAPIProvider)

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
