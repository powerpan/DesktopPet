//
// SlackInboundAutoReplyService.swift
// Slack 入站 user 消息后的自动续写 assistant（与对话面板同一模型链路）。
//

import Foundation

@MainActor
struct SlackInboundAutoReplyService {
    let slackSync: SlackSyncController
    let session: AgentSessionStore
    let settings: AgentSettingsStore
    let deskMirror: DeskMirrorModel
    let client: AgentClient
    let multimodalLimits: MultimodalAttachmentLimitsStore

    func performAutoReplyIfPossible(channelId: UUID) async {
        guard slackSync.integrationConfig.enabled else { return }
        if session.isSending { return }
        guard let channel = session.conversation.channel(id: channelId) else { return }

        let key = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider)
        var systemPrompt = settings.systemPrompt
        systemPrompt += "\n\n（本条或本轮上下文中的部分 user 消息可能来自 Slack；请像平常一样以桌宠身份自然回复。）"
        if settings.attachKeySummary {
            let s = deskMirror.recentKeyLabelsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                systemPrompt += "\n\n（可选上下文）用户近期键入标签摘要：\(s.prefix(200))"
            }
        }

        let userMessages: [AgentAPIChatUserMessage]
        do {
            userMessages = try ChatMultimodalAPIBuilder.openAICompatibleUserMessages(
                from: channel,
                limits: multimodalLimits
            )
        } catch {
            session.lastError = error.localizedDescription
            return
        }
        guard userMessages.contains(where: { $0.role == "user" }) else { return }

        let extended = userMessages.contains { u in
            u.parts.contains { p in
                if case .imageJPEG = p { return true }
                if case .imageData = p { return true }
                return false
            }
        }

        session.setSending(true)
        session.lastError = nil
        defer { session.setSending(false) }

        do {
            let reply = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: systemPrompt,
                userMessages: userMessages,
                temperature: settings.temperature,
                maxTokens: settings.maxTokens,
                extendedTimeout: extended
            )
            session.appendAssistantInChannel(channelId: channelId, text: reply)
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}
