//
// ChatMultimodalAPIBuilder.swift
// 将本地 `ChatChannel` 转为 `AgentAPIChatUserMessage` 列表供 `AgentClient.completeChat` 使用。
//

import Foundation

enum ChatMultimodalAPIBuilder {
    /// 仅打包 `user` / `assistant`；忽略 `system` 气泡（系统提示单独由调用方传入）。
    @MainActor
    static func openAICompatibleUserMessages(
        from channel: ChatChannel,
        limits: MultimodalAttachmentLimitsStore
    ) throws -> [AgentAPIChatUserMessage] {
        var out: [AgentAPIChatUserMessage] = []
        for m in channel.messages {
            if m.role == "assistant" {
                out.append(AgentAPIChatUserMessage(role: "assistant", text: m.content))
            } else if m.role == "user" {
                if m.attachments.isEmpty {
                    out.append(AgentAPIChatUserMessage(role: "user", text: m.content))
                } else {
                    var parts: [AgentAPIChatContentPart] = []
                    let trimmed = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parts.append(.text(trimmed))
                    }
                    for ref in m.attachments {
                        guard let data = ChatAttachmentStorage.read(messageId: m.id, ref: ref) else { continue }
                        let sub = try ChatMultimodalAttachmentCodec.partsFromPersistedRef(
                            data: data,
                            ref: ref,
                            limits: limits
                        )
                        parts.append(contentsOf: sub)
                    }
                    if parts.isEmpty {
                        out.append(AgentAPIChatUserMessage(role: "user", text: m.content))
                    } else {
                        out.append(AgentAPIChatUserMessage(role: "user", parts: parts))
                    }
                }
            }
        }
        return out
    }
}
