//
// AgentConversationStore.swift
// 多会话频道：UserDefaults + Codable 持久化。
//

import Foundation
import SwiftUI

private enum AgentConversationKeys {
    static let channels = "DesktopPet.agent.conversation.channels.v1"
    static let activeChannelId = "DesktopPet.agent.conversation.activeChannelId.v1"
}

@MainActor
final class AgentConversationStore: ObservableObject {
    @Published private(set) var channels: [ChatChannel] = []
    @Published private(set) var activeChannelId: UUID = UUID()

    private let defaults = UserDefaults.standard

    init() {
        load()
        if channels.isEmpty {
            let ch = Self.makeDefaultChannel()
            channels = [ch]
            activeChannelId = ch.id
            persist()
        } else if !channels.contains(where: { $0.id == activeChannelId }) {
            activeChannelId = channels[0].id
            persist()
        }
    }

    private static func makeDefaultChannel() -> ChatChannel {
        ChatChannel(
            id: UUID(),
            title: "默认会话",
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )
    }

    private func load() {
        if let idString = defaults.string(forKey: AgentConversationKeys.activeChannelId),
           let id = UUID(uuidString: idString) {
            activeChannelId = id
        }
        if let data = defaults.data(forKey: AgentConversationKeys.channels),
           let decoded = try? JSONDecoder().decode([ChatChannel].self, from: data) {
            channels = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(channels) {
            defaults.set(data, forKey: AgentConversationKeys.channels)
        }
        defaults.set(activeChannelId.uuidString, forKey: AgentConversationKeys.activeChannelId)
    }

    var activeMessages: [ChatMessage] {
        channels.first(where: { $0.id == activeChannelId })?.messages ?? []
    }

    func channel(id: UUID) -> ChatChannel? {
        channels.first { $0.id == id }
    }

    func switchChannel(id: UUID) {
        guard channels.contains(where: { $0.id == id }) else { return }
        activeChannelId = id
        persist()
    }

    /// 新建空会话并切到该频道。
    @discardableResult
    func createEmptyChannel(title: String? = nil) -> UUID {
        let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let t = raw.isEmpty ? defaultTitleForNewChannel() : raw
        let ch = ChatChannel(id: UUID(), title: t, createdAt: Date(), updatedAt: Date(), messages: [])
        channels.append(ch)
        activeChannelId = ch.id
        persist()
        return ch.id
    }

    /// 从触发旁白接续：新建频道，首条为猫猫的 assistant 上文。
    @discardableResult
    func createChannelFromTriggerPrologue(_ text: String) -> UUID {
        let t = defaultTitleForNewChannel(prefix: "触发续聊")
        let msgs: [ChatMessage] = [
            ChatMessage(role: "assistant", content: text),
            ChatMessage(role: "system", content: "（上文来自条件触发的旁白，你可直接回复猫猫。）"),
        ]
        let ch = ChatChannel(id: UUID(), title: t, createdAt: Date(), updatedAt: Date(), messages: msgs)
        channels.append(ch)
        activeChannelId = ch.id
        persist()
        return ch.id
    }

    func renameChannel(id: UUID, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = channels.firstIndex(where: { $0.id == id }) else { return }
        var ch = channels[i]
        ch.title = t
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
    }

    func deleteChannel(id: UUID) {
        guard channels.count > 1, let i = channels.firstIndex(where: { $0.id == id }) else { return }
        ChatAttachmentStorage.deleteAttachments(for: channels[i].messages)
        channels.remove(at: i)
        if activeChannelId == id {
            activeChannelId = channels[0].id
        }
        persist()
    }

    func clearActiveChannelMessages() {
        guard let i = channels.firstIndex(where: { $0.id == activeChannelId }) else { return }
        var ch = channels[i]
        ChatAttachmentStorage.deleteAttachments(for: ch.messages)
        ch.messages = []
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
    }

    func appendUser(
        _ text: String,
        uploads: [(filename: String, mimeType: String, data: Data)] = []
    ) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !uploads.isEmpty, let i = channels.firstIndex(where: { $0.id == activeChannelId }) else { return }
        var ch = channels[i]
        let msgId = UUID()
        var refs: [ChatAttachmentRef] = []
        for u in uploads {
            let ref = ChatAttachmentRef(
                id: UUID(),
                filename: u.filename,
                mimeType: u.mimeType,
                byteCount: u.data.count
            )
            do {
                try ChatAttachmentStorage.write(messageId: msgId, ref: ref, data: u.data)
                refs.append(ref)
            } catch {
                ChatAttachmentStorage.deleteAll(messageId: msgId)
                return
            }
        }
        let display = t.isEmpty
            ? (refs.isEmpty ? "" : "（已附 \(refs.count) 个文件）")
            : t
        let msg = ChatMessage(id: msgId, role: "user", content: display, attachments: refs)
        ch.messages.append(msg)
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
        postConversationAppend(channelId: activeChannelId, message: msg, origin: "local")
    }

    func appendAssistant(_ text: String) {
        guard let i = channels.firstIndex(where: { $0.id == activeChannelId }) else { return }
        var ch = channels[i]
        let msg = ChatMessage(role: "assistant", content: text)
        ch.messages.append(msg)
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
        postConversationAppend(channelId: activeChannelId, message: msg, origin: "local")
    }

    /// 向指定频道追加猫猫回复（用于 Slack 入站自动续写等）；**不**切换当前选中频道。
    func appendAssistantInChannel(channelId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = channels.firstIndex(where: { $0.id == channelId }) else { return }
        var ch = channels[i]
        let msg = ChatMessage(role: "assistant", content: trimmed)
        ch.messages.append(msg)
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
        postConversationAppend(channelId: channelId, message: msg, origin: "local")
    }

    func appendSystemNotice(_ text: String) {
        guard let i = channels.firstIndex(where: { $0.id == activeChannelId }) else { return }
        var ch = channels[i]
        ch.messages.append(ChatMessage(role: "system", content: text))
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
    }

    /// 向指定本地会话频道追加系统提示（不切换当前选中频道）。
    func appendSystemNoticeInChannel(channelId: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = channels.firstIndex(where: { $0.id == channelId }) else { return }
        var ch = channels[i]
        ch.messages.append(ChatMessage(role: "system", content: t))
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
    }

    /// Slack 入站：写入指定本地频道，**不**切换当前选中频道。
    func appendSlackInboundUser(
        channelId: UUID,
        text: String,
        slackTs: String,
        slackChannelId: String,
        uploads: [(filename: String, mimeType: String, data: Data)] = []
    ) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !uploads.isEmpty, let i = channels.firstIndex(where: { $0.id == channelId }) else { return }
        var ch = channels[i]
        let msgId = UUID()
        var refs: [ChatAttachmentRef] = []
        for u in uploads {
            let ref = ChatAttachmentRef(
                id: UUID(),
                filename: u.filename,
                mimeType: u.mimeType,
                byteCount: u.data.count
            )
            do {
                try ChatAttachmentStorage.write(messageId: msgId, ref: ref, data: u.data)
                refs.append(ref)
            } catch {
                ChatAttachmentStorage.deleteAll(messageId: msgId)
                return
            }
        }
        let display: String = {
            if t.isEmpty { return refs.isEmpty ? "" : "（Slack 附件 \(refs.count) 个）" }
            if refs.isEmpty { return t }
            return t + "\n（含 \(refs.count) 个 Slack 附件）"
        }()
        let msg = ChatMessage(
            id: msgId,
            role: "user",
            content: display,
            slackMessageTs: slackTs,
            slackChannelId: slackChannelId,
            attachments: refs
        )
        ch.messages.append(msg)
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
        postConversationAppend(channelId: channelId, message: msg, origin: "slack")
    }

    /// Slack 入站：对方频道里出现 assistant 文本（少见，预留）。
    func appendSlackInboundAssistant(channelId: UUID, text: String, slackTs: String, slackChannelId: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = channels.firstIndex(where: { $0.id == channelId }) else { return }
        var ch = channels[i]
        let msg = ChatMessage(
            role: "assistant",
            content: t,
            slackMessageTs: slackTs,
            slackChannelId: slackChannelId
        )
        ch.messages.append(msg)
        ch.updatedAt = Date()
        channels[i] = ch
        persist()
        postConversationAppend(channelId: channelId, message: msg, origin: "slack")
    }

    private func postConversationAppend(channelId: UUID, message: ChatMessage, origin: String) {
        guard message.role == "user" || message.role == "assistant" else { return }
        var userInfo: [String: Any] = [
            DesktopPetNotificationUserInfoKey.conversationAppendChannelId: channelId.uuidString,
            DesktopPetNotificationUserInfoKey.conversationAppendMessageId: message.id.uuidString,
            DesktopPetNotificationUserInfoKey.conversationAppendRole: message.role,
            DesktopPetNotificationUserInfoKey.conversationAppendContent: message.content,
            DesktopPetNotificationUserInfoKey.conversationAppendOrigin: origin,
        ]
        if let ts = message.slackMessageTs {
            userInfo[DesktopPetNotificationUserInfoKey.conversationAppendSlackTs] = ts
        }
        if let ch = message.slackChannelId {
            userInfo[DesktopPetNotificationUserInfoKey.conversationAppendSlackChannelId] = ch
        }
        if !message.attachments.isEmpty {
            userInfo[DesktopPetNotificationUserInfoKey.conversationAppendAttachmentCount] = message.attachments.count
        }
        NotificationCenter.default.post(name: .desktopPetConversationDidAppendMessage, object: nil, userInfo: userInfo)
    }

    private func defaultTitleForNewChannel(prefix: String = "新会话") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .short
        return "\(prefix) \(f.string(from: Date()))"
    }

    /// 隐私/重置：仅保留一个空会话频道。
    func resetToSingleDefaultChannel() {
        for ch in channels {
            ChatAttachmentStorage.deleteAttachments(for: ch.messages)
        }
        let ch = Self.makeDefaultChannel()
        channels = [ch]
        activeChannelId = ch.id
        persist()
    }
}
