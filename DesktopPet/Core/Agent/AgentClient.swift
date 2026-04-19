//
// AgentClient.swift
// DeepSeek/OpenAI 兼容 chat/completions（非流式 MVP）；支持多模态 user 消息（文本 + JPEG）。
//

import Foundation
import SwiftUI

enum AgentClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case http(Int, String)
    case decode
    case emptyChoices

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "未配置 API Key（请在智能体设置中填写并保存）。"
        case .invalidURL: return "Base URL 无效。"
        case let .http(code, body): return "HTTP \(code): \(body.prefix(200))"
        case .decode: return "响应解析失败。"
        case .emptyChoices: return "模型未返回内容。"
        }
    }
}

/// 单条 user 消息中的内容片（OpenAI Chat Completions 兼容 JSON）。
enum AgentAPIChatContentPart: Sendable {
    case text(String)
    case imageJPEG(Data)

    fileprivate func jsonObject() -> [String: Any] {
        switch self {
        case let .text(t):
            return ["type": "text", "text": t]
        case let .imageJPEG(data):
            let b64 = data.base64EncodedString()
            return [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(b64)",
                ],
            ]
        }
    }
}

/// 一条发给 API 的 user 消息（纯文本或多模态）。
struct AgentAPIChatUserMessage: Sendable {
    var role: String
    var parts: [AgentAPIChatContentPart]

    init(role: String = "user", parts: [AgentAPIChatContentPart]) {
        self.role = role
        self.parts = parts
    }

    init(role: String = "user", text: String) {
        self.role = role
        self.parts = [.text(text)]
    }

    fileprivate func jsonObject() -> [String: Any] {
        if parts.count == 1, case let .text(t) = parts[0] {
            return ["role": role, "content": t]
        }
        return ["role": role, "content": parts.map { $0.jsonObject() }]
    }
}

@MainActor
final class AgentClient {
    private let urlSession: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 180
        urlSession = URLSession(configuration: cfg)
    }

    /// 纯文本消息（兼容旧调用方）。
    func completeChat(
        baseURL: String,
        model: String,
        apiKey: String?,
        systemPrompt: String,
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let apiMessages = messages.map { row -> AgentAPIChatUserMessage in
            let role = row["role"] ?? "user"
            let content = row["content"] ?? ""
            return AgentAPIChatUserMessage(role: role, text: content)
        }
        return try await completeChat(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userMessages: apiMessages,
            temperature: temperature,
            maxTokens: maxTokens,
            extendedTimeout: false
        )
    }

    /// 支持多模态 user 消息（如截屏旁白）。
    func completeChat(
        baseURL: String,
        model: String,
        apiKey: String?,
        systemPrompt: String,
        userMessages: [AgentAPIChatUserMessage],
        temperature: Double,
        maxTokens: Int,
        extendedTimeout: Bool
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw AgentClientError.missingAPIKey }
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/v1/chat/completions") else { throw AgentClientError.invalidURL }

        var payloadMessages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for u in userMessages {
            payloadMessages.append(u.jsonObject())
        }

        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": payloadMessages,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        if extendedTimeout {
            req.timeoutInterval = 240
        }

        let session = extendedTimeout ? Self.longTimeoutSession : urlSession
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AgentClientError.http(-1, "") }
        guard (200 ... 299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AgentClientError.http(http.statusCode, bodyStr)
        }
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first,
            let msg = first["message"] as? [String: Any]
        else {
            throw AgentClientError.decode
        }
        let text = try Self.assistantText(from: msg)
        if text.isEmpty { throw AgentClientError.emptyChoices }
        return text
    }

    private static let longTimeoutSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 240
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    private static func assistantText(from message: [String: Any]) throws -> String {
        if let s = message["content"] as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let arr = message["content"] as? [[String: Any]] {
            let pieces = arr.compactMap { dict -> String? in
                guard (dict["type"] as? String) == "text" else { return nil }
                return dict["text"] as? String
            }
            return pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw AgentClientError.decode
    }
}

// MARK: - SwiftUI 环境注入（设置页调试试跑等）

private struct DesktopPetAgentClientKey: EnvironmentKey {
    static let defaultValue: AgentClient? = nil
}

extension EnvironmentValues {
    /// 由 `AppCoordinator.presentAgentSettingsWindow` 注入，供成长调试「试跑 AI」等使用。
    var desktopPetAgentClient: AgentClient? {
        get { self[DesktopPetAgentClientKey.self] }
        set { self[DesktopPetAgentClientKey.self] = newValue }
    }
}
