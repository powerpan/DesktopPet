//
// AgentSettingsView.swift
// DeepSeek 连接、人格、触发器与隐私相关开关（API Key 仅钥匙串）。
//

import SwiftUI

struct AgentSettingsView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore

    @State private var apiKeyDraft: String = ""
    @State private var keychainMessage: String?
    @State private var showKeyboardRiskAlert = false
    @State private var showScreenSnapInfo = false
    @AppStorage("DesktopPet.agent.keyboardMasterRiskAcknowledged") private var keyboardRiskAcknowledged = false
    @State private var showConversationChannelsSheet = false
    @State private var showTriggerSpeechHistorySheet = false

    var body: some View {
        TabView {
            connectionTab
                .tabItem { Label("连接", systemImage: "link") }
            personalityTab
                .tabItem { Label("人格", systemImage: "theatermasks") }
            triggersTab
                .tabItem { Label("触发器", systemImage: "bolt.horizontal") }
            privacyTab
                .tabItem { Label("隐私", systemImage: "hand.raised") }
        }
        .frame(minWidth: 480, minHeight: 520)
        .padding(12)
        .onAppear {
            apiKeyDraft = KeychainStore.readAPIKey() ?? ""
        }
        .alert("键盘模式触发", isPresented: $showKeyboardRiskAlert) {
            Button("取消", role: .cancel) {}
            Button("我已了解风险") {
                keyboardRiskAcknowledged = true
                settings.keyboardTriggerMasterEnabled = true
            }
        } message: {
            Text("开启后，应用会监听全局按键以匹配你配置的「模式串」，用于触发智能体旁白。不会把原始键入全文写入磁盘；但仍属于敏感能力，请仅在信任本机与源码时使用。")
        }
        .alert("截屏触发", isPresented: $showScreenSnapInfo) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("截屏/画面理解类触发仍在规划中。即使打开总开关，当前版本也不会发起截屏或上传图像。")
        }
    }

    private var connectionTab: some View {
        Form {
            Section {
                TextField("Base URL", text: $settings.baseURL)
                TextField("模型 id", text: $settings.model)
            } header: {
                Text("服务端")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL：OpenAI 兼容接口的根地址，须含 https://，不要拼 /v1/... 路径；DeepSeek 官方一般为 https://api.deepseek.com。")
                    Text("模型 id：在控制台创建或查看，例如 deepseek-chat；填错会返回 HTTP 4xx。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                SecureField("粘贴 DeepSeek API Key", text: $apiKeyDraft)
                HStack {
                    Button("保存到钥匙串") {
                        do {
                            try KeychainStore.saveAPIKey(apiKeyDraft)
                            keychainMessage = "已保存。"
                            session.lastError = nil
                        } catch {
                            keychainMessage = error.localizedDescription
                        }
                    }
                    Button("清除钥匙串中的 Key", role: .destructive) {
                        KeychainStore.deleteAPIKey()
                        apiKeyDraft = ""
                        keychainMessage = "已清除。"
                    }
                }
                if let keychainMessage {
                    Text(keychainMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("API Key（钥匙串）")
            } footer: {
                Text("仅保存在本机钥匙串，不会写入 UserDefaults 或明文文件。保存后若对话里仍提示未配置，可先关闭再打开对话面板刷新状态。")
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

            Section {
                Button("查看正式会话频道…") {
                    showConversationChannelsSheet = true
                }
                Button("查看条件触发旁白历史…") {
                    showTriggerSpeechHistorySheet = true
                }
                Button("清空当前频道消息") {
                    session.clearSession()
                }
                Button("清空条件触发旁白历史", role: .destructive) {
                    session.triggerHistory.clearAll()
                }
                Button("重置所有手动会话频道", role: .destructive) {
                    session.resetAllConversationChannelsToDefault()
                }
            } header: {
                Text("会话与历史")
            } footer: {
                Text("多会话频道与消息保存在 UserDefaults；「清空当前频道」只影响当前选中会话。「旁白历史」记录条件触发文案（最多约 200 条）。重置会话会删除所有频道并恢复为单一空会话。在频道表中进入某频道可浏览全部消息，并可一键切回该频道并打开对话面板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showConversationChannelsSheet) {
            ConversationChannelsManagerSheet(isPresented: $showConversationChannelsSheet)
                .environmentObject(session)
        }
        .sheet(isPresented: $showTriggerSpeechHistorySheet) {
            TriggerSpeechHistoryListSheet(isPresented: $showTriggerSpeechHistorySheet)
                .environmentObject(session)
        }
    }

    private var personalityTab: some View {
        Form {
            Section {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 200)
            } header: {
                Text("系统提示（人格）")
            } footer: {
                Text("每次请求都会作为 system 消息发给模型，用来设定语气、称呼、回答语言等。对话面板里的聊天内容会接在它的后面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private var triggersTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("触发器在满足条件时会自动请求模型写一句短旁白：写入旁白历史，并以宠窗旁云气泡展示。")
                    Text("轻点气泡会关闭气泡、以该旁白为上下文新建一个手动会话频道，并打开对话面板续聊。")
                    Text("「气泡测试」不调用模型：在规则编辑页选择短/长固定文案后点「立即触发」，用于检查气泡布局与续聊流程。")
                    Text("每条规则有独立冷却，避免刷屏。定时与随机空闲适合日常使用；键盘与前台应用属于进阶能力，请谨慎开启。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("列表") {
                ForEach(settings.triggers) { rule in
                    TriggerRuleRow(rule: rule)
                }
                .onDelete { idx in
                    for i in idx {
                        let id = settings.triggers[i].id
                        settings.removeTrigger(id: id)
                    }
                }
                Menu("添加触发器") {
                    ForEach(AgentTriggerKind.allCases.filter { $0 != .screenSnap }) { k in
                        Button(k.displayName) {
                            settings.triggers.append(.new(kind: k))
                        }
                    }
                    Button("截屏（占位）") {
                        settings.triggers.append(.new(kind: .screenSnap))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            Section {
                Toggle("在对话请求中附带键入摘要", isOn: $settings.attachKeySummary)
                Text("依赖桌镜的键位标签摘要，可能暴露你正在输入的大致内容；默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("请求增强（高风险）")
            } footer: {
                Text("开启后，会把桌镜里显示的「键位标签摘要」拼进发给模型的系统提示或触发旁白请求，仅在你主动发消息或触发器触发时才会上网。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("允许键盘模式触发", isOn: Binding(
                    get: { settings.keyboardTriggerMasterEnabled },
                    set: { newValue in
                        if newValue {
                            if keyboardRiskAcknowledged {
                                settings.keyboardTriggerMasterEnabled = true
                            } else {
                                showKeyboardRiskAlert = true
                            }
                        } else {
                            settings.keyboardTriggerMasterEnabled = false
                        }
                    }
                ))
                Text("总开关关闭时，所有「键盘模式」类规则都不会匹配。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("截屏类触发（总开关）", isOn: $settings.screenSnapTriggerMasterEnabled)
                    .onChange(of: settings.screenSnapTriggerMasterEnabled) { _, on in
                        if on { showScreenSnapInfo = true }
                    }
                Text("当前版本不会截屏；此开关为后续能力预留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("进阶触发总开关")
            } footer: {
                Text("键盘总闸：关闭后，所有「键盘模式」类触发器都不会匹配子串。截屏总闸：当前版本无实际截屏逻辑。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TriggerRuleRow: View {
    let rule: AgentTriggerRule
    @EnvironmentObject private var settings: AgentSettingsStore
    @State private var editing: AgentTriggerRule?
    @State private var showEditor = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.kind.displayName)
                    .font(.headline)
                Text(subtitle(for: rule))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
            Button("编辑") {
                editing = rule
                showEditor = true
            }
        }
        .sheet(isPresented: $showEditor) {
            if let editing {
                TriggerRuleEditorSheet(rule: editing, isPresented: $showEditor)
                    .environmentObject(settings)
            }
        }
        .onChange(of: showEditor) { _, open in
            if !open { editing = nil }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.triggers.first(where: { $0.id == rule.id })?.enabled ?? false },
            set: { newVal in
                settings.updateTrigger(id: rule.id) { $0.enabled = newVal }
            }
        )
    }

    private func subtitle(for r: AgentTriggerRule) -> String {
        switch r.kind {
        case .timer: return "每 \(r.timerIntervalMinutes) 分钟"
        case .randomIdle: return "空闲 ≥\(r.randomIdleSeconds)s，概率 \(Int(r.randomIdleProbability * 100))%"
        case .keyboardPattern: return "模式「\(r.keyboardPattern)」"
        case .frontApp: return "前台包含「\(r.frontAppNameContains)」"
        case .screenSnap: return "占位，不触发"
        case .bubbleTest: return "编辑内选手动触发短/长气泡"
        }
    }
}

private struct TriggerRuleEditorSheet: View {
    @State var rule: AgentTriggerRule
    @EnvironmentObject private var settings: AgentSettingsStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $rule.kind) {
                        ForEach(AgentTriggerKind.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .disabled(true)
                    Stepper("冷却（秒）: \(Int(rule.cooldownSeconds))", value: $rule.cooldownSeconds, in: 30 ... 3600, step: 30)
                        .disabled(rule.kind == .bubbleTest)
                } header: {
                    Text("基本")
                } footer: {
                    Text(rule.kind == .bubbleTest
                         ? "气泡测试仅用手动按钮触发，不走模型；冷却对自动轮询无影响（本条不参与定时评估）。"
                         : "冷却：两次触发之间的最短间隔（秒）。触发一次后会进入冷却，期间即使条件仍满足也不会再请求。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                switch rule.kind {
                case .timer:
                    Section {
                        Stepper("间隔（分钟）: \(rule.timerIntervalMinutes)", value: $rule.timerIntervalMinutes, in: 1 ... 24 * 60)
                    } header: {
                        Text("定时")
                    } footer: {
                        Text("从上一次触发完成起算，每隔这么多分钟最多触发一次（仍受冷却下限约束）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .randomIdle:
                    Section {
                        Stepper("空闲秒数: \(rule.randomIdleSeconds)", value: $rule.randomIdleSeconds, in: 10 ... 3600, step: 10)
                        HStack {
                            Text("触发概率")
                            Slider(value: $rule.randomIdleProbability, in: 0.01 ... 0.5, step: 0.01)
                            Text(String(format: "%.0f%%", rule.randomIdleProbability * 100))
                                .font(.caption.monospacedDigit())
                        }
                    } header: {
                        Text("随机空闲")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("仅在宠物窗口可见时评估。空闲秒数：无键鼠活动达到该秒数后才可能触发。")
                            Text("概率：每次抽样时掷骰，数值越大越容易触发；建议保持较低以免打扰。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .keyboardPattern:
                    Section {
                        Text("仅匹配模式串（最近按键缓冲），不保存全文日志。需打开「隐私」中的总开关。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("要匹配的子串", text: $rule.keyboardPattern)
                    } header: {
                        Text("键盘模式")
                    } footer: {
                        Text("在「最近按键」字符缓冲里查找是否包含该子串；大小写敏感。需已授予辅助功能。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .frontApp:
                    Section {
                        TextField("应用名包含（本地化名称子串）", text: $rule.frontAppNameContains)
                    } header: {
                        Text("前台应用")
                    } footer: {
                        Text("当前台应用切换到名称包含该子串的应用时触发一次（例如 Xcode、Safari）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .screenSnap:
                    Section {
                        Text("当前版本不会触发；占位以便后续接入 ScreenCaptureKit 等能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("截屏")
                    } footer: {
                        Text("开启后也不会请求截屏权限；与「隐私」Tab 中的截屏总开关为后续版本预留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .bubbleTest:
                    Section {
                        Picker("测试文案", selection: $rule.testBubbleSample) {
                            ForEach(TestBubbleSample.allCases) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button("立即触发测试气泡") {
                            NotificationCenter.default.post(
                                name: .desktopPetFireTestBubble,
                                object: nil,
                                userInfo: [DesktopPetNotificationUserInfoKey.testBubbleSample: rule.testBubbleSample.rawValue]
                            )
                        }
                    } header: {
                        Text("气泡测试")
                    } footer: {
                        Text("不请求大模型，仅弹出与真实触发相同的旁白气泡与历史记录，便于自测布局。可在上方切换「短 / 长」后再点按钮对比效果。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑触发器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        settings.upsertTrigger(rule)
                        isPresented = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 360)
    }
}
