//
// AgentClient.swift
// DeepSeek/OpenAI 兼容 chat/completions（非流式 MVP）。
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

@MainActor
final class AgentClient {
    private let urlSession: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 180
        urlSession = URLSession(configuration: cfg)
    }

    func completeChat(
        baseURL: String,
        model: String,
        apiKey: String?,
        systemPrompt: String,
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw AgentClientError.missingAPIKey }
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/v1/chat/completions") else { throw AgentClientError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": [["role": "system", "content": systemPrompt]] + messages,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AgentClientError.http(-1, "") }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentClientError.http(http.statusCode, body)
        }
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first,
            let msg = first["message"] as? [String: Any],
            let content = msg["content"] as? String
        else {
            throw AgentClientError.decode
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw AgentClientError.emptyChoices }
        return text
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
