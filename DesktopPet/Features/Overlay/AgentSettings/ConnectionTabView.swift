//
// ConnectionTabView.swift
// 智能体设置 ·「连接」Tab：服务商、Base URL、模型、钥匙串 Key、Slack、生成参数。
//

import SwiftUI

struct ConnectionTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var slackSync: SlackSyncController

    @State private var apiKeyDraft: String = ""
    @State private var keychainMessage: String?
    @State private var slackTokenDraft: String = ""
    @State private var slackTokenMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("当前服务商", selection: Binding(
                    get: { settings.activeAPIProvider },
                    set: { new in
                        Task { @MainActor in
                            settings.setActiveAPIProvider(new)
                            apiKeyDraft = KeychainStore.readAPIKey(forProvider: new) ?? ""
                        }
                    }
                )) {
                    ForEach(AgentAPIProvider.allCases) { p in
                        Text(p.pickerLabel).tag(p)
                    }
                }
                .onChange(of: settings.activeAPIProvider) { _, new in
                    apiKeyDraft = KeychainStore.readAPIKey(forProvider: new) ?? ""
                }
            } header: {
                Text("模型配置")
            } footer: {
                Text("每一套服务商各自保存 Base URL、模型 id 与 API Key。切换时会载入该套已保存的地址与模型；请为当前选中的服务商单独粘贴并保存 Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                TextField("Base URL", text: $settings.baseURL)
                TextField("模型 id", text: $settings.model)
            } header: {
                Text("服务端（当前：\(settings.activeAPIProvider.pickerLabel)）")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL：OpenAI 兼容 Chat Completions 的根地址，须含 https://，**不要**手动拼 `/v1/chat/completions`（应用会自动追加）。")
                    Text("DeepSeek 示例：https://api.deepseek.com")
                    Text("通义千问（DashScope 兼容模式）示例：https://dashscope.aliyuncs.com/compatible-mode；模型如 qwen-vl-plus（截屏多模态）、qwen-turbo 等以控制台为准。")
                    Text("自定义：可填其它兼容网关；模型 id 填对方文档中的名称。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                SecureField("粘贴当前服务商的 API Key", text: $apiKeyDraft)
                HStack {
                    Button("保存到钥匙串") {
                        do {
                            try KeychainStore.saveAPIKey(apiKeyDraft, forProvider: settings.activeAPIProvider)
                            keychainMessage = "已保存（\(settings.activeAPIProvider.pickerLabel)）。"
                            session.lastError = nil
                        } catch {
                            keychainMessage = error.localizedDescription
                        }
                    }
                    Button("清除当前服务商的 Key", role: .destructive) {
                        KeychainStore.deleteAPIKey(forProvider: settings.activeAPIProvider)
                        apiKeyDraft = ""
                        keychainMessage = "已清除（\(settings.activeAPIProvider.pickerLabel)）。"
                    }
                }
                if let keychainMessage {
                    Text(keychainMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("API Key（钥匙串 · \(settings.activeAPIProvider.pickerLabel)）")
            } footer: {
                Text("仅保存在本机钥匙串，不会写入 UserDefaults 或明文文件；各服务商使用不同钥匙串账户，互不影响。保存后若对话里仍提示未配置，可先关闭再打开对话面板刷新状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("启用 Slack 同步", isOn: Binding(
                    get: { slackSync.integrationConfig.enabled },
                    set: { v in
                        var c = slackSync.integrationConfig
                        c.enabled = v
                        slackSync.updateIntegrationConfig(c)
                    }
                ))
                TextField("Slack 频道 ID（C…）", text: Binding(
                    get: { slackSync.integrationConfig.monitoredChannelId },
                    set: { v in
                        var c = slackSync.integrationConfig
                        c.monitoredChannelId = v
                        slackSync.updateIntegrationConfig(c)
                    }
                ))
                Stepper(
                    "轮询间隔：\(Int(slackSync.integrationConfig.pollIntervalSeconds)) 秒",
                    value: Binding(
                        get: { slackSync.integrationConfig.pollIntervalSeconds },
                        set: { v in
                            var c = slackSync.integrationConfig
                            c.pollIntervalSeconds = min(120, max(3, v))
                            slackSync.updateIntegrationConfig(c)
                        }
                    ),
                    in: 3 ... 120,
                    step: 1
                )
                Toggle("入站（Slack → 本地）", isOn: Binding(
                    get: { slackSync.integrationConfig.syncInbound },
                    set: { v in
                        var c = slackSync.integrationConfig
                        c.syncInbound = v
                        slackSync.updateIntegrationConfig(c)
                    }
                ))
                Toggle("出站（本地 → Slack）", isOn: Binding(
                    get: { slackSync.integrationConfig.syncOutbound },
                    set: { v in
                        var c = slackSync.integrationConfig
                        c.syncOutbound = v
                        slackSync.updateIntegrationConfig(c)
                    }
                ))
                SecureField("Slack Bot Token（xoxb-…，仅钥匙串）", text: $slackTokenDraft)
                HStack {
                    Button("保存 Token 到钥匙串") {
                        do {
                            try KeychainStore.saveSlackBotToken(slackTokenDraft)
                            slackTokenMessage = "已保存 Slack Token。"
                        } catch {
                            slackTokenMessage = error.localizedDescription
                        }
                    }
                    Button("清除 Token", role: .destructive) {
                        KeychainStore.deleteSlackBotToken()
                        slackTokenDraft = ""
                        slackTokenMessage = "已清除 Slack Token。"
                    }
                }
                if let slackTokenMessage {
                    Text(slackTokenMessage).font(.caption).foregroundStyle(.secondary)
                }
                Button("将监控频道绑定到当前本地会话") {
                    slackSync.bindMonitoredChannelToActiveSession(session)
                }
                Button("重置该频道「跳过历史」标记") {
                    slackSync.resetChannelInitializationMarker()
                }
                Text(slackSync.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !slackSync.bindings.isEmpty {
                    Text("已绑定 \(slackSync.bindings.count) 条")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Slack")
            } footer: {
                Text("在 Slack 频道发送 `!pet new 标题` 可新建本地会话并绑定。首次连接某频道会跳过历史回放，仅同步之后的新消息。出站会同步当前绑定频道内你发送的 user/assistant 消息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                HStack {
                    Text("温度 (temperature)")
                    Slider(value: $settings.temperature, in: 0 ... 1.5, step: 0.05)
                    Text(String(format: "%.2f", settings.temperature))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                Stepper("max_tokens：\(settings.maxTokens)", value: $settings.maxTokens, in: 64 ... 4096, step: 64)
            } header: {
                Text("生成参数")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("温度：越高回答越随机、越有创意；越低越保守、越稳定。一般聊天约 0.6～0.9。")
                    Text("max_tokens：模型单次回复最多生成的 token 数（约等于字数上限）；越大越耗额度与等待时间。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKeyDraft = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider) ?? ""
            slackTokenDraft = KeychainStore.readSlackBotToken() ?? ""
        }
    }
}
