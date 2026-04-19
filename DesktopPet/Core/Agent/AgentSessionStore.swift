//
// AgentSessionStore.swift
// 多频道会话代理：委托 `AgentConversationStore` 持久化；触发旁白历史见 `TriggerSpeechHistoryStore`。
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AgentSessionStore: ObservableObject {
    let conversation: AgentConversationStore
    let triggerHistory: TriggerSpeechHistoryStore

    @Published private(set) var isSending = false
    @Published var lastError: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        conversation = AgentConversationStore()
        triggerHistory = TriggerSpeechHistoryStore()
        conversation.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        triggerHistory.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - 当前频道投影

    var messages: [ChatMessage] { conversation.activeMessages }

    var channels: [ChatChannel] { conversation.channels }

    var activeChannelId: UUID { conversation.activeChannelId }

    var activeChannel: ChatChannel? { conversation.channel(id: conversation.activeChannelId) }

    func selectChannel(id: UUID) {
        conversation.switchChannel(id: id)
    }

    @discardableResult
    func createNewEmptyChannel(title: String? = nil) -> UUID {
        conversation.createEmptyChannel(title: title)
    }

    /// 点击触发气泡后续聊：新建频道，首条为猫猫旁白作为上文。
    @discardableResult
    func startSessionFromTrigger(text: String) -> UUID {
        conversation.createChannelFromTriggerPrologue(text)
    }

    func renameChannel(id: UUID, title: String) {
        conversation.renameChannel(id: id, title: title)
    }

    func deleteChannel(id: UUID) {
        conversation.deleteChannel(id: id)
    }

    func clearSession() {
        conversation.clearActiveChannelMessages()
        lastError = nil
    }

    func appendUser(
        _ text: String,
        uploads: [(filename: String, mimeType: String, data: Data)] = []
    ) {
        conversation.appendUser(text, uploads: uploads)
    }

    func appendAssistant(_ text: String) {
        conversation.appendAssistant(text)
    }

    func appendAssistantInChannel(channelId: UUID, text: String) {
        conversation.appendAssistantInChannel(channelId: channelId, text: text)
    }

    func appendSystemNotice(_ text: String) {
        conversation.appendSystemNotice(text)
    }

    func appendSystemNoticeInChannel(channelId: UUID, text: String) {
        conversation.appendSystemNoticeInChannel(channelId: channelId, text: text)
    }

    func appendSlackInboundUser(
        channelId: UUID,
        text: String,
        slackTs: String,
        slackChannelId: String,
        uploads: [(filename: String, mimeType: String, data: Data)] = []
    ) {
        conversation.appendSlackInboundUser(
            channelId: channelId,
            text: text,
            slackTs: slackTs,
            slackChannelId: slackChannelId,
            uploads: uploads
        )
    }

    func appendSlackInboundAssistant(channelId: UUID, text: String, slackTs: String, slackChannelId: String) {
        conversation.appendSlackInboundAssistant(channelId: channelId, text: text, slackTs: slackTs, slackChannelId: slackChannelId)
    }

    func setSending(_ v: Bool) {
        isSending = v
    }

    /// 重置所有手动会话为单一空频道（不清理触发旁白历史）。
    func resetAllConversationChannelsToDefault() {
        conversation.resetToSingleDefaultChannel()
        lastError = nil
    }
}
