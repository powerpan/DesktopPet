//
// ChatOverlayView.swift
// 智能体对话叠加层：多会话、多模态 user 消息（图片 / PDF / 文本文件等）。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct PendingLocalAttachment: Identifiable {
    let id = UUID()
    var filename: String
    var data: Data
}

struct ChatOverlayView: View {
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var agentSettings: AgentSettingsStore
    @EnvironmentObject private var petMenuSettings: SettingsViewModel
    @EnvironmentObject private var deskMirror: DeskMirrorModel
    @EnvironmentObject private var routeBus: AppRouteBus
    @EnvironmentObject private var multimodalLimits: MultimodalAttachmentLimitsStore
    @Environment(\.desktopPetAgentClient) private var agentClient: AgentClient?

    @State private var draft: String = ""
    @State private var keychainConfigured: Bool = false
    @State private var showRenameAlert = false
    @State private var renameDraft: String = ""
    @State private var showDeleteConfirm = false
    @State private var pendingAttachments: [PendingLocalAttachment] = []
    @State private var showFileImporter = false

    private static let importerTypes: [UTType] = [.image, .pdf, .plainText, .json, .commaSeparatedText]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("七七猫 · 对话")
                        .font(.headline)
                    Text(keychainConfigured ? "钥匙串：已检测到 API Key" : "钥匙串：未检测到 API Key（请在智能体工作台 → 连接中保存）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    channelToolbar
                    if let ch = session.activeChannel {
                        Text("当前：\(ch.title) · 更新 \(formatted(ch.updatedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    MarkdownInlineText(
                        source: "支持图片与常见文本类文件（多模态）；大小上限在智能体工作台 **集成** 中配置。Slack 入站附件使用同一套限额。",
                        font: .caption2
                    )
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button {
                    routeBus.closeChatOverlay()
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

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { p in
                            pendingChip(p)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 72)
            }

            HStack(alignment: .center, spacing: 8) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("添加图片或文件")
                .disabled(session.isSending)

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
        .desktopPetPanelLiquidGlass(
            cornerRadius: 14,
            liquidGlassEnabled: petMenuSettings.isLiquidGlassChromeEnabled,
            glassVariant: petMenuSettings.liquidGlassVariant
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.importerTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    let started = url.startAccessingSecurityScopedResource()
                    defer {
                        if started { url.stopAccessingSecurityScopedResource() }
                    }
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let name = url.lastPathComponent
                    pendingAttachments.append(PendingLocalAttachment(filename: name, data: data))
                }
            case .failure(let err):
                session.lastError = err.localizedDescription
            }
        }
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

    private func pendingChip(_ p: PendingLocalAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 96, height: 56)
            attachmentThumbView(data: p.data, filename: p.filename)
                .frame(width: 88, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button {
                pendingAttachments.removeAll { $0.id == p.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    @ViewBuilder
    private func attachmentThumbView(data: Data, filename: String) -> some View {
        let mime = ChatMultimodalAttachmentCodec.declaredMime(filename: filename, data: data)
        if mime.hasPrefix("image/"), let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 2) {
                Image(systemName: "doc.text")
                Text(filename)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
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

            Button {
                routeBus.presentAgentSettingsTab(index: AgentSettingsWorkspaceTab.conversation.rawValue)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("会话与历史、旁白与清理…")
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
                VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    if m.slackMessageTs != nil {
                        Text("Slack")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2), in: Capsule())
                    }
                    if !m.attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(m.attachments) { ref in
                                    if let d = ChatAttachmentStorage.read(messageId: m.id, ref: ref) {
                                        attachmentThumbView(data: d, filename: ref.filename)
                                            .frame(width: 72, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 260)
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
        guard !t.isEmpty || !pendingAttachments.isEmpty else { return }

        var uploads: [(filename: String, mimeType: String, data: Data)] = []
        for p in pendingAttachments {
            do {
                _ = try ChatMultimodalAttachmentCodec.partsFromLocalUpload(
                    data: p.data,
                    filename: p.filename,
                    limits: multimodalLimits
                )
                let mime = ChatMultimodalAttachmentCodec.declaredMime(filename: p.filename, data: p.data)
                uploads.append((p.filename, mime, p.data))
            } catch {
                session.lastError = error.localizedDescription
                return
            }
        }

        draft = ""
        pendingAttachments.removeAll()
        session.appendUser(t, uploads: uploads)
        session.setSending(true)
        session.lastError = nil
        guard let client = agentClient else {
            session.lastError = "未注入 AgentClient。"
            session.setSending(false)
            return
        }
        let key = KeychainStore.readAPIKey(forProvider: agentSettings.activeAPIProvider)

        var systemPrompt = agentSettings.systemPrompt
        if agentSettings.attachKeySummary {
            let s = deskMirror.recentKeyLabelsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                systemPrompt += "\n\n（可选上下文）用户近期键入标签摘要：\(s.prefix(200))"
            }
        }

        guard let channel = session.activeChannel else {
            session.lastError = "无当前会话。"
            session.setSending(false)
            return
        }

        let userMessages: [AgentAPIChatUserMessage]
        do {
            userMessages = try ChatMultimodalAPIBuilder.openAICompatibleUserMessages(
                from: channel,
                limits: multimodalLimits
            )
        } catch {
            session.lastError = error.localizedDescription
            session.setSending(false)
            return
        }

        let extended = userMessages.contains { u in
            u.parts.contains { p in
                if case .imageJPEG = p { return true }
                if case .imageData = p { return true }
                return false
            }
        }

        do {
            let reply = try await client.completeChat(
                baseURL: agentSettings.baseURL,
                model: agentSettings.model,
                apiKey: key,
                systemPrompt: systemPrompt,
                userMessages: userMessages,
                temperature: agentSettings.temperature,
                maxTokens: agentSettings.maxTokens,
                extendedTimeout: extended
            )
            session.appendAssistant(reply)
        } catch {
            session.lastError = error.localizedDescription
        }
        session.setSending(false)
    }
}
