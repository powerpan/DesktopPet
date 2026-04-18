//
// AgentSettingsView.swift
// DeepSeek 连接、人格、触发器与隐私相关开关（API Key 仅钥匙串）。
//

import SwiftUI

struct AgentSettingsView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var petCare: PetCareModel
    @Environment(\.desktopPetAgentClient) private var desktopPetAgentClient: AgentClient?

    @State private var apiKeyDraft: String = ""
    @State private var keychainMessage: String?
    @State private var showKeyboardRiskAlert = false
    @State private var showScreenSnapInfo = false
    @AppStorage("DesktopPet.agent.keyboardMasterRiskAcknowledged") private var keyboardRiskAcknowledged = false
    @State private var showConversationChannelsSheet = false
    @State private var showTriggerSpeechHistorySheet = false
    @State private var showTriggerUserPromptHistorySheet = false
    @State private var showNewKeyboardTriggerPrivacyHint = false
    @State private var selectedSettingsTab = 0
    @State private var growthDebugRandomPreview: String?
    @State private var growthDebugRandomTestUseAI = true
    @State private var growthDebugRandomTestBusy = false

    private static let pendingAgentSettingsTabKey = "DesktopPet.ui.pendingAgentSettingsTab"

    var body: some View {
        TabView(selection: $selectedSettingsTab) {
            connectionTab
                .tabItem { Label("连接", systemImage: "link") }
                .tag(0)
            personalityTab
                .tabItem { Label("人格", systemImage: "theatermasks") }
                .tag(1)
            triggersTab
                .tabItem { Label("触发器", systemImage: "bolt.horizontal") }
                .tag(2)
            privacyTab
                .tabItem { Label("隐私", systemImage: "hand.raised") }
                .tag(3)
            growthTab
                .tabItem { Label("成长", systemImage: "leaf.fill") }
                .tag(4)
        }
        .frame(minWidth: 480, minHeight: 520)
        .padding(12)
        .onAppear {
            apiKeyDraft = KeychainStore.readAPIKey() ?? ""
            if let v = UserDefaults.standard.object(forKey: Self.pendingAgentSettingsTabKey) as? Int {
                UserDefaults.standard.removeObject(forKey: Self.pendingAgentSettingsTabKey)
                if (0 ... 4).contains(v) {
                    selectedSettingsTab = v
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .desktopPetPresentAgentSettingsTab)) { note in
            let tab = note.userInfo?[DesktopPetNotificationUserInfoKey.agentSettingsTabIndex] as? Int ?? 0
            selectedSettingsTab = min(4, max(0, tab))
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
        .alert("请打开键盘模式总开关", isPresented: $showNewKeyboardTriggerPrivacyHint) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("你刚添加了「键盘模式」触发器，但「隐私」Tab 中的「允许键盘模式触发」总开关仍为关闭，规则不会生效。请切换到「隐私」阅读说明并打开开关。")
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
                Button("查看触发器发给模型的请求…") {
                    showTriggerUserPromptHistorySheet = true
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
                Text("多会话频道与消息保存在 UserDefaults；「清空当前频道」只影响当前选中会话。「旁白历史」记录模型返回的旁白正文；「发给模型的请求」记录同一次触发里作为 user 发给大模型的全文（占位符已替换，最多约 200 条与旁白历史共用条数）。清空旁白历史会同时清空这两类展示所依赖的数据。重置会话会删除所有频道并恢复为单一空会话。")
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
        .sheet(isPresented: $showTriggerUserPromptHistorySheet) {
            TriggerUserPromptHistorySheet(isPresented: $showTriggerUserPromptHistorySheet)
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
                Text("每次请求都会作为 system 消息发给模型，用来设定语气、称呼、回答语言等；对话面板里的聊天内容会接在它的后面。条件触发的旁白请求会把同一段人格文字拼在 user 消息最开头（旁白单独走一套温度与 max_tokens，见「触发器」Tab），与长对话的 system 用法区分开。")
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
                    Text("在规则编辑页底部可点「立即触发当前触发器」，用当前表单内容向模型请求一次旁白（与自动触发相同链路），便于试跑提示语与路由。")
                    Text("「饲养互动」在喂食/戳戳成功时请求旁白（不在此列表里自动轮询）；数值摘要写入模板占位符 {careContext}。首次升级会插入一条默认规则（默认关闭），可在编辑页打开开关。")
                    Text("每条规则有独立冷却，避免刷屏。定时与随机空闲适合日常使用；键盘与前台应用属于进阶能力，请谨慎开启。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text("温度 (temperature)")
                    Slider(value: $settings.triggerDefaultTemperature, in: 0 ... 1.5, step: 0.05)
                    Text(String(format: "%.2f", settings.triggerDefaultTemperature))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                Stepper("max_tokens：\(settings.triggerDefaultMaxTokens)", value: $settings.triggerDefaultMaxTokens, in: 32 ... 1024, step: 32)
            } header: {
                Text("旁白生成参数（默认）")
            } footer: {
                Text("仅作用于「条件触发 / 立即触发」的短旁白请求，与「连接」Tab 里长对话的温度、max_tokens 相互独立。各条触发器可在编辑页单独覆盖；未覆盖时使用这里的默认值。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
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
                            if k == .keyboardPattern, !settings.keyboardTriggerMasterEnabled {
                                showNewKeyboardTriggerPrivacyHint = true
                            }
                        }
                    }
                    Button("截屏（占位）") {
                        settings.triggers.append(.new(kind: .screenSnap))
                    }
                }
            } header: {
                Text("列表")
            } footer: {
                Text("macOS 上分组表单里通常没有「左滑删除」；请点每行右侧废纸篓图标，或在打开「编辑」后使用工具栏里的「删除」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("开启后，会把桌镜里显示的「键位标签摘要」拼进长对话的系统提示或触发旁白请求的 user 内容，仅在你主动发消息或触发器触发时才会上网。")
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

    private var growthTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("喂食冷却")
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Picker("小时", selection: growthFeedCooldownHourBinding) {
                            ForEach(0 ... 24, id: \.self) { h in
                                Text("\(h)").tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("小时")
                        .frame(minWidth: 88)

                        Text("小时")

                        Picker("分钟", selection: growthFeedCooldownMinuteBinding) {
                            ForEach(growthFeedCooldownMinuteChoices, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("分钟")
                        .frame(minWidth: 88)
                        .disabled(growthFeedCooldownHourDisplay == 24)

                        Text("分钟")
                    }
                    Text("当前约 \(growthFeedCooldownLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper(
                    "戳戳冷却：\(petCare.petCooldownSeconds) 秒",
                    value: $petCare.petCooldownSeconds,
                    in: 5 ... 600,
                    step: 5
                )
            } header: {
                Text("猫猫互动")
            } footer: {
                Text("喂食：5 分钟～24 小时（用「小时 + 分钟」选择；满 24 小时时分钟固定为 00）。戳戳：5～600 秒。会写入本机偏好，重启后仍生效；冷却中是否立刻按新值生效取决于距离上次操作的时间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                HStack {
                    Text("每小时能量衰减")
                    Spacer()
                    Text(String(format: "%.1f%%", petCare.growthConfig.energyDrainPerHour * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthEnergyDrainBinding,
                    in: 0 ... 0.15,
                    step: 0.002
                )
                HStack {
                    Text("每小时心情衰减")
                    Spacer()
                    Text(String(format: "%.1f%%", petCare.growthConfig.moodDrainPerHour * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthMoodDrainBinding,
                    in: 0 ... 0.12,
                    step: 0.002
                )
                HStack {
                    Text("随机事件密度")
                    Spacer()
                    Text("\(petCare.growthConfig.randomEventDensityPercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: growthDensityBinding,
                    in: 0 ... 100,
                    step: 1
                )
                Toggle("允许 AI 生成成长事件", isOn: growthAIEnabledBinding)
                Stepper(
                    "AI 事件最小间隔：\(String(format: "%.0f", petCare.growthConfig.aiGrowthEventsMinIntervalHours)) 小时",
                    value: growthAIMinHoursBinding,
                    in: 1 ... 48,
                    step: 1
                )
            } header: {
                Text("成长参数")
            } footer: {
                Text("每小时衰减在宠物隐藏时也会累计。若距离上次结算已超过 3 小时（例如久未打开应用），只会按小时补扣心情/能量，不会补抽随机事件；回到 3 小时内后恢复按密度抽样（午间等时段略更容易）。开启 AI 后，部分事件会请求模型生成 JSON（失败则自动用本地事件）；会消耗 API。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                let month = petCare.currentMonthSummary()
                Text("本月（\(month.yearMonthKey)）有陪伴的天数：\(month.daysWithCompanion) 天")
                Text("本月累计陪伴：\(month.totalCompanionSeconds / 60) 分钟 · 喂食 \(month.totalFeedCount) 次 · 戳戳 \(month.totalPetCount) 次 · 成长事件 \(month.totalDecayEvents) 次")
                Text("本月有陪伴日的平均陪伴：\(month.averageCompanionMinutesPerActiveDay) 分钟/天 · 最佳连续有陪伴：\(month.bestStreakDaysWithCompanion) 天")
                Divider().padding(.vertical, 4)
                Text("近 7 天陪伴（分钟）")
                    .font(.subheadline.weight(.semibold))
                ForEach(petCare.lastNDaysCompanionMinutes(7), id: \.dayKey) { row in
                    HStack {
                        Text(row.dayKey)
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(row.minutes) 分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("统计预览")
            } footer: {
                Text("陪伴时长仅在宠物窗口可见时累计；统计按本机日历日写入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                if petCare.state.recentDecayEvents.isEmpty {
                    Text("暂无记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(petCare.state.recentDecayEvents.prefix(15)) { ev in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(ev.source == .ai ? "AI" : "本地")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ev.source == .ai ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                                Text(ev.reasonCode)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(shortDate(ev.occurredAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(ev.reasonText)
                                .font(.caption)
                            Text("心情 \(signedPct(ev.moodDelta)) · 能量 \(signedPct(ev.energyDelta))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("最近成长事件")
            } footer: {
                Text("事件会轻微调整心情/能量并记入当日统计；列表最多保留 80 条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                if let d = petCare.state.lastDecayAt {
                    Text("lastDecayAt（ISO8601）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(growthDebugISO8601(d))
                        .font(.caption.monospacedDigit())
                        .textSelection(.enabled)
                    Text("Unix 秒：\(Int64(d.timeIntervalSince1970))")
                        .font(.caption.monospacedDigit())
                        .textSelection(.enabled)
                    let gap = Date().timeIntervalSince(d)
                    Text("距今：\(formatGrowthDebugSeconds(gap))（\(gap <= 3 * 3600 ? "≤3 小时：真实结算可掷随机" : ">3 小时：真实结算仅固定衰减")）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("lastDecayAt：nil（尚未写入锚点）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("当前心情 \(String(format: "%.3f", petCare.state.mood)) · 能量 \(String(format: "%.3f", petCare.state.energy))（仅展示）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Toggle("试跑使用 AI（默认开：每次点击都请求模型）", isOn: $growthDebugRandomTestUseAI)
                    .disabled(growthDebugRandomTestBusy)
                Button("随机事件试跑（不改数值 / 不改 lastDecayAt）") {
                    runGrowthDebugRandomTest()
                }
                .disabled(growthDebugRandomTestBusy)
                if growthDebugRandomTestBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                if let growthDebugRandomPreview {
                    Text(growthDebugRandomPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("调试")
            } footer: {
                Text("关闭「试跑使用 AI」时，只调用本地事件池与随机数；打开时每次点击都会向当前 Base URL / 模型发一次 JSON 试跑请求（不写回状态）。两种模式均不修改 lastDecayAt 与心情/能量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private func runGrowthDebugRandomTest() {
        if growthDebugRandomTestUseAI {
            growthDebugRandomTestBusy = true
            Task { @MainActor in
                defer { growthDebugRandomTestBusy = false }
                await runGrowthDebugAITest()
            }
        } else {
            runGrowthDebugLocalRandomTest()
        }
    }

    private func runGrowthDebugLocalRandomTest() {
        var rng = SplitMix64(seed: UInt64.random(in: 1 ... UInt64.max))
        let at = Date()
        if let ev = PetLocalGrowthEventPool.sampleEvent(at: at, calendar: .current, rng: &rng) {
            let h = Calendar.current.component(.hour, from: at)
            growthDebugRandomPreview = """
            [本地池]
            抽样时刻本地小时=\(h)
            code=\(ev.reasonCode)
            \(ev.reasonText)
            moodΔ=\(String(format: "%.4f", ev.moodDelta)) · energyΔ=\(String(format: "%.4f", ev.energyDelta))
            """
        } else {
            growthDebugRandomPreview = "（未返回事件，极少见）"
        }
    }

    private func runGrowthDebugAITest() async {
        guard let client = desktopPetAgentClient else {
            growthDebugRandomPreview = "「试跑使用 AI」已打开，但未注入 AgentClient。"
            return
        }
        let at = Date()
        let recentCodes = petCare.state.recentDecayEvents.prefix(20).map(\.reasonCode)
        let recentTexts = petCare.state.recentDecayEvents.prefix(12).map(\.reasonText)
        let creativitySeed = Int.random(in: 0 ..< 1_000_000)
        let user = PetGrowthAI.buildUserPrompt(
            hourStart: at,
            mood: petCare.state.mood,
            energy: petCare.state.energy,
            recentEventCodes: recentCodes,
            recentReasonTexts: recentTexts,
            creativitySeed: creativitySeed,
            localTemplateSummary: PetGrowthAI.localTemplateSummaryForPrompt()
        )
        let key = KeychainStore.readAPIKey()
        let messages: [[String: String]] = [["role": "user", "content": user]]
        do {
            let text = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: "你只输出 JSON。不要输出任何其它字符。",
                messages: messages,
                temperature: 1.08,
                maxTokens: 512
            )
            if let parsed = PetGrowthAI.parseEvents(from: text), let ev = parsed.first {
                let h = Calendar.current.component(.hour, from: at)
                growthDebugRandomPreview = """
                [AI 试跑 · 已解析] seed=\(creativitySeed)
                请求时刻本地小时=\(h)
                code=\(ev.reasonCode)
                \(ev.reasonText)
                moodΔ=\(String(format: "%.4f", ev.moodDelta)) · energyΔ=\(String(format: "%.4f", ev.energyDelta))
                """
            } else {
                growthDebugRandomPreview = """
                [AI 试跑 · 解析失败]
                模型原文（截断）：
                \(String(text.prefix(800)))
                """
            }
        } catch {
            growthDebugRandomPreview = "[AI 试跑 · 请求失败]\n\(error.localizedDescription)"
        }
    }

    private func growthDebugISO8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func formatGrowthDebugSeconds(_ t: TimeInterval) -> String {
        if t < 120 { return String(format: "%.0f 秒", t) }
        if t < 3600 { return String(format: "%.1f 分钟", t / 60) }
        return String(format: "%.2f 小时", t / 3600)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func signedPct(_ d: Double) -> String {
        let p = d * 100
        if p >= 0 { return String(format: "+%.0f%%", p) }
        return String(format: "%.0f%%", p)
    }

    private var growthEnergyDrainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.energyDrainPerHour },
            set: { v in
                var c = petCare.growthConfig
                c.energyDrainPerHour = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthMoodDrainBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.moodDrainPerHour },
            set: { v in
                var c = petCare.growthConfig
                c.moodDrainPerHour = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthDensityBinding: Binding<Double> {
        Binding(
            get: { Double(petCare.growthConfig.randomEventDensityPercent) },
            set: { v in
                var c = petCare.growthConfig
                c.randomEventDensityPercent = Int(v.rounded())
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthAIEnabledBinding: Binding<Bool> {
        Binding(
            get: { petCare.growthConfig.aiGrowthEventsEnabled },
            set: { v in
                var c = petCare.growthConfig
                c.aiGrowthEventsEnabled = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthAIMinHoursBinding: Binding<Double> {
        Binding(
            get: { petCare.growthConfig.aiGrowthEventsMinIntervalHours },
            set: { v in
                var c = petCare.growthConfig
                c.aiGrowthEventsMinIntervalHours = v
                petCare.growthConfig = PetGrowthConfig.clamped(c)
            }
        )
    }

    private var growthFeedCooldownLabel: String {
        let s = petCare.feedCooldownSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0, m > 0 { return "\(h) 小时 \(m) 分钟" }
        if h > 0 { return "\(h) 小时" }
        if m > 0 { return "\(m) 分钟" }
        return "\(s) 秒"
    }

    /// 与 `PetCareModel` 一致：总分钟数 ∈ \[5, 1440\]（5 分钟～24 小时）。
    private func growthFeedCooldownClampedTotalMinutes() -> Int {
        min(24 * 60, max(5, petCare.feedCooldownSeconds / 60))
    }

    private func growthFeedCooldownSetTotalMinutes(_ total: Int) {
        let t = min(24 * 60, max(5, total))
        petCare.feedCooldownSeconds = t * 60
    }

    private var growthFeedCooldownHourDisplay: Int {
        growthFeedCooldownClampedTotalMinutes() / 60
    }

    private var growthFeedCooldownMinuteChoices: [Int] {
        let h = growthFeedCooldownHourDisplay
        if h == 24 { return [0] }
        if h == 0 { return Array(5 ... 59) }
        return Array(0 ... 59)
    }

    private var growthFeedCooldownHourBinding: Binding<Int> {
        Binding(
            get: { growthFeedCooldownHourDisplay },
            set: { newH in
                let tot = growthFeedCooldownClampedTotalMinutes()
                let m = tot % 60
                let newTotal: Int
                if newH == 24 {
                    newTotal = 24 * 60
                } else if newH == 0 {
                    newTotal = max(5, m)
                } else {
                    newTotal = newH * 60 + m
                }
                growthFeedCooldownSetTotalMinutes(newTotal)
            }
        )
    }

    private var growthFeedCooldownMinuteBinding: Binding<Int> {
        Binding(
            get: {
                let tot = growthFeedCooldownClampedTotalMinutes()
                let h = tot / 60
                let m = tot % 60
                if h == 24 { return 0 }
                if h == 0 { return max(5, m) }
                return m
            },
            set: { newM in
                let tot = growthFeedCooldownClampedTotalMinutes()
                let h = tot / 60
                let clampedM: Int
                if h == 0 {
                    clampedM = min(59, max(5, newM))
                } else if h == 24 {
                    clampedM = 0
                } else {
                    clampedM = min(59, max(0, newM))
                }
                growthFeedCooldownSetTotalMinutes(h * 60 + clampedM)
            }
        )
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
            Button {
                settings.removeTrigger(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("删除此触发器")
            .accessibilityLabel("删除此触发器")
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
        let routeHint: String = {
            let n = r.routes.count
            guard n > 0 else { return "" }
            let mx = r.routes.map(\.priority).max() ?? 0
            return " · \(n)条路由·最高优先级\(mx)"
        }()
        switch r.kind {
        case .timer: return "每 \(r.timerIntervalMinutes) 分钟\(routeHint)"
        case .randomIdle: return "空闲 ≥\(r.randomIdleSeconds)s，概率 \(Int(r.randomIdleProbability * 100))%\(routeHint)"
        case .keyboardPattern:
            if r.routes.isEmpty, !r.keyboardPattern.isEmpty { return "模式「\(r.keyboardPattern)」" }
            return "键盘路由\(routeHint)"
        case .frontApp:
            if r.routes.isEmpty, !r.frontAppNameContains.isEmpty { return "前台包含「\(r.frontAppNameContains)」" }
            return "前台路由\(routeHint)"
        case .screenSnap: return "占位，不触发\(routeHint)"
        case .careInteraction: return "饲养面板成功后·旁白\(routeHint)"
        }
    }
}

/// 旁白请求模板中占位符的说明（默认模板与单条路由模板共用）。
private struct PromptPlaceholderHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("占位符（须一字不差、含花括号）可在模板任意位置插入；未写的占位符不会出现在最终发给模型的文字里。")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("· {extra} — 由应用自动拼好的一段「场景说明」：固定带有「（系统触发：某某类型）」；若你在「隐私」里打开了「附带键入摘要」，也会把截断后的键位摘要接在这同一段后面。建议保留，方便模型知道是谁在触发。")
                Text("· {triggerKind} — 替换为当前规则的类型中文名，例如「键盘模式」「定时」「随机空闲」。")
                Text("· {matchedCondition} — 替换为本次命中的那条旁白路由的条件摘要（例如「按键含「abc」且 空闲≥120s」），便于模型理解命中分支。")
                Text("· {keySummary} — 仅键入摘要的短片段（与 {extra} 里可能带的摘要同源）；未开「附带键入摘要」时为空字符串。适合在模板中间单独引用摘要、而不想整段复述 {extra} 时使用。")
                Text("· {careContext} — 仅「饲养互动」类型：喂食或戳戳成功时，由应用自动填入心情/能量变化与陪伴时长等摘要；未触发饲养操作或试跑占位时可能为空。")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text("示例：「用户可能刚输入了敏感内容。{extra} 请用两句简体中文温柔提醒。」若不写任何占位符，则整段模板会原样作为 user 消息发送。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TriggerRuleEditorSheet: View {
    @State var rule: AgentTriggerRule
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore
    @Binding var isPresented: Bool
    @State private var editingRouteIndex: Int?
    @State private var showKeyboardMasterOffOnFinish = false

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
                } header: {
                    Text("基本")
                } footer: {
                    Text("冷却：两次触发之间的最短间隔（秒）。触发一次后会进入冷却，期间即使条件仍满足也不会再请求。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if rule.kind == .keyboardPattern, !settings.keyboardTriggerMasterEnabled {
                    Section {
                        Label {
                            Text("「隐私」Tab 中的「允许键盘模式触发」总开关当前为关闭，本键盘规则不会匹配按键。请切换到「隐私」阅读风险提示后打开开关。")
                                .font(.callout)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("需要操作")
                    }
                }

                Section {
                    TextEditor(text: $rule.defaultPromptTemplate)
                        .font(.body)
                        .frame(minHeight: 72)
                    PromptPlaceholderHelp()
                } header: {
                    Text("默认旁白请求（无路由命中）")
                } footer: {
                    Text("发给模型的一条 user 消息（user role）。当没有任何旁白路由的条件被满足时，使用本模板。整段留空则使用应用内置默认句式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                    if rule.routes.isEmpty {
                        Text("尚未配置路由：将使用上方默认模板；键盘类还可回退到下方「旧版单一模式串」。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(rule.routes.enumerated()), id: \.element.id) { index, route in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("优先级 \(route.priority)")
                                    .font(.subheadline.weight(.semibold))
                                Text(routeSummary(route))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(route.enabled ? "开" : "关")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("编辑") {
                                editingRouteIndex = index
                            }
                            Button {
                                removeRoute(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("删除此旁白路由")
                            .accessibilityLabel("删除此旁白路由")
                        }
                    }
                    .onDelete { idx in
                        for i in idx.sorted(by: >) {
                            removeRoute(at: i)
                        }
                    }

                    Button("添加旁白路由") {
                        let nextP = (rule.routes.map(\.priority).max() ?? 0) + 1
                        let tmpl = AgentTriggerRule.newRoutePromptTemplate(for: rule.kind)
                        let conds: [TriggerRouteCondition] = {
                            switch rule.kind {
                            case .keyboardPattern: return [.keyboardContains("")]
                            case .frontApp: return [.frontAppContains("")]
                            case .timer, .randomIdle, .screenSnap, .careInteraction: return [.always]
                            }
                        }()
                        rule.routes.append(
                            TriggerPromptRoute(enabled: true, priority: nextP, conditions: conds, promptTemplate: tmpl)
                        )
                        editingRouteIndex = rule.routes.count - 1
                    }

                    if rule.kind == .keyboardPattern {
                        HStack(spacing: 10) {
                            Button("插入示例：密码安全") {
                                insertPasswordRouteExample()
                            }
                            Button("插入示例：表白关键词") {
                                insertLoveRouteExamples()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("旁白路由（优先级高先匹配）")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("每条路由内多个条件为 AND。键盘类路由至少包含一个「按键包含」且子串非空，否则不会匹配。同一次触发只选用一条路由的提示语。")
                        Text("删除：点每行右侧废纸篓；macOS 分组表单里左滑删除往往不可用。")
                    }
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
                        TextField("旧版单一模式串（仅当上方「路由表」为空时生效）", text: $rule.keyboardPattern)
                    } header: {
                        Text("键盘模式（兼容）")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("推荐在「旁白路由」里为不同子串配置不同提示语；优先级数字越大越先匹配。此处旧字段仅在路由表为空时作为单条子串回退；大小写敏感。需已授予辅助功能。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !settings.keyboardTriggerMasterEnabled {
                                Text("总开关关闭时引擎不会评估键盘子串；请务必到「隐私」打开「允许键盘模式触发」。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .frontApp:
                    Section {
                        TextField("旧版应用名子串（仅当路由表为空时生效）", text: $rule.frontAppNameContains)
                    } header: {
                        Text("前台应用（兼容）")
                    } footer: {
                        Text("推荐在「旁白路由」里用「前台包含」条件写多条。此处旧字段仅在路由表为空时回退；切换应用时大小写不敏感匹配本地化名称。")
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
                case .careInteraction:
                    Section {
                        Text("由饲养面板的「喂食」「戳戳」在**成功生效**后触发（动作处于冷却失败时不会请求模型）。应用会把当前心情、能量、今日陪伴时长及本次数值变化写入旁白模板的 {careContext}。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("冷却：两次饲养旁白请求之间的最短间隔；与喂食 4 小时、戳戳 30 秒的动作冷却无关，用于防止连点造成重复请求。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } header: {
                        Text("饲养互动")
                    } footer: {
                        Text("列表中若有多条「饲养互动」规则，仅**第一条已启用**的会收到面板事件；可在模板中用 {careContext}、{extra}、{matchedCondition} 等占位符。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section {
                    Toggle("单独设置旁白温度", isOn: Binding(
                        get: { rule.triggerTemperature != nil },
                        set: { on in
                            if on {
                                if rule.triggerTemperature == nil {
                                    rule.triggerTemperature = settings.triggerDefaultTemperature
                                }
                            } else {
                                rule.triggerTemperature = nil
                            }
                        }
                    ))
                    if rule.triggerTemperature != nil {
                        HStack {
                            Text("温度")
                            Slider(
                                value: Binding(
                                    get: { rule.triggerTemperature ?? settings.triggerDefaultTemperature },
                                    set: { rule.triggerTemperature = $0 }
                                ),
                                in: 0 ... 1.5,
                                step: 0.05
                            )
                            Text(String(format: "%.2f", rule.triggerTemperature ?? settings.triggerDefaultTemperature))
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    Toggle("单独设置旁白 max_tokens", isOn: Binding(
                        get: { rule.triggerMaxTokens != nil },
                        set: { on in
                            if on {
                                if rule.triggerMaxTokens == nil {
                                    rule.triggerMaxTokens = settings.triggerDefaultMaxTokens
                                }
                            } else {
                                rule.triggerMaxTokens = nil
                            }
                        }
                    ))
                    if rule.triggerMaxTokens != nil {
                        Stepper(
                            "max_tokens: \(rule.triggerMaxTokens ?? settings.triggerDefaultMaxTokens)",
                            value: Binding(
                                get: { rule.triggerMaxTokens ?? settings.triggerDefaultMaxTokens },
                                set: { rule.triggerMaxTokens = $0 }
                            ),
                            in: 32 ... 1024,
                            step: 32
                        )
                    }
                } header: {
                    Text("旁白生成参数（本条）")
                } footer: {
                    Text("关闭开关时使用「触发器」Tab 的默认温度与 max_tokens。从气泡进入长对话后，发送消息仍使用「连接」Tab 的设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                    Button("立即触发当前触发器") {
                        postForceFireTriggerNotification()
                    }
                    .disabled(session.isSending || rule.kind == .screenSnap)
                } header: {
                    Text("试跑")
                } footer: {
                    Text("使用当前编辑页中的表单内容（含未点「完成」的修改）向模型请求一次旁白；成功后会出现旁白气泡并写入「旁白历史」与「发给模型的请求」。与自动触发相同会更新该规则在列表中的「上次触发」时间。路由选择会先按当前真实环境（前台名、按键缓冲、空闲等）匹配；若无一命中（例如在设置窗试跑「前台含 Xcode」），会按优先级回退到第一条启用的旁白路由模板，便于预览文案。截屏类规则仍为占位，不会请求模型；正在发送时按钮不可用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: Binding(
                get: { editingRouteIndex != nil },
                set: { if !$0 { editingRouteIndex = nil } }
            )) {
                if let i = editingRouteIndex, rule.routes.indices.contains(i) {
                    TriggerPromptRouteEditorSheet(rule: $rule, routeIndex: i)
                        .frame(minWidth: 440, minHeight: 520)
                }
            }
            .navigationTitle("编辑触发器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("删除", role: .destructive) {
                        settings.removeTrigger(id: rule.id)
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if rule.kind == .keyboardPattern, !settings.keyboardTriggerMasterEnabled {
                            showKeyboardMasterOffOnFinish = true
                        } else {
                            settings.upsertTrigger(rule)
                            isPresented = false
                        }
                    }
                }
            }
            .alert("键盘模式总开关未开启", isPresented: $showKeyboardMasterOffOnFinish) {
                Button("仍保存并关闭") {
                    settings.upsertTrigger(rule)
                    isPresented = false
                }
                Button("留在编辑页", role: .cancel) {}
            } message: {
                Text("「隐私」Tab 中的「允许键盘模式触发」仍为关闭，键盘规则不会生效。若要启用匹配，请切换到「隐私」阅读说明并打开总开关。")
            }
        }
        .frame(minWidth: 400, minHeight: 360)
    }

    private func postForceFireTriggerNotification() {
        guard let data = try? JSONEncoder().encode(rule),
              let json = String(data: data, encoding: .utf8) else { return }
        NotificationCenter.default.post(
            name: .desktopPetForceFireTriggerRule,
            object: nil,
            userInfo: [DesktopPetNotificationUserInfoKey.triggerRuleJSON: json]
        )
    }

    /// 删除旁白路由并修正正在编辑的 sheet 下标，避免索引错乱。
    private func removeRoute(at index: Int) {
        guard rule.routes.indices.contains(index) else { return }
        rule.routes.remove(at: index)
        if let ei = editingRouteIndex {
            if ei == index {
                editingRouteIndex = nil
            } else if ei > index {
                editingRouteIndex = ei - 1
            }
        }
    }

    private func routeSummary(_ route: TriggerPromptRoute) -> String {
        let cond = route.conditions.isEmpty
            ? "（无条件）"
            : route.conditions.map(conditionLabel).joined(separator: " 且 ")
        let promptPreview = route.promptTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(36)
        return "\(cond) → 「\(promptPreview)\(promptPreview.count >= 36 ? "…" : "")」"
    }

    private func conditionLabel(_ c: TriggerRouteCondition) -> String {
        switch c {
        case .always: return "始终"
        case let .keyboardContains(s): return "按键含「\(s)」"
        case let .frontAppContains(s): return "前台含「\(s)」"
        case let .idleAtLeastSeconds(n): return "空闲≥\(n)s"
        case let .timerElapsedAtLeastMinutes(m): return "距上次≥\(m)分"
        }
    }

    private func insertPasswordRouteExample() {
        rule.routes.append(
            TriggerPromptRoute(
                enabled: true,
                priority: 10,
                conditions: [.keyboardContains("ABC123456")],
                promptTemplate: "检测到用户近期键入里出现了示例密码串 ABC123456。请用一两句简体中文温柔提醒用户保管好密码、避免泄露与截图外泄，不要用教训口吻。{extra}"
            )
        )
    }

    private func insertLoveRouteExamples() {
        rule.routes.append(
            TriggerPromptRoute(
                enabled: true,
                priority: 9,
                conditions: [.keyboardContains("我爱你")],
                promptTemplate: "用户键入了「我爱你」相关字串。请用一两句简体中文温柔、轻松地鼓励用户：想念对方就合适地表达出来或去见一面，语气要暖。{extra}"
            )
        )
        rule.routes.append(
            TriggerPromptRoute(
                enabled: true,
                priority: 8,
                conditions: [.keyboardContains("woaini")],
                promptTemplate: "用户键入了「woaini」拼音式表白。请用一两句简体中文轻松鼓励用户把心意传达给对方或约见面，语气俏皮可爱。{extra}"
            )
        )
    }
}

// MARK: - 旁白路由编辑

private struct TriggerPromptRouteEditorSheet: View {
    @Binding var rule: AgentTriggerRule
    let routeIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TriggerPromptRoute

    init(rule: Binding<AgentTriggerRule>, routeIndex: Int) {
        _rule = rule
        self.routeIndex = routeIndex
        _draft = State(initialValue: rule.wrappedValue.routes[routeIndex])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("优先级（越大越先匹配）: \(draft.priority)", value: $draft.priority, in: 0 ... 999, step: 1)
                    Toggle("启用该路由", isOn: $draft.enabled)
                } header: {
                    Text("路由")
                }

                Section {
                    TextEditor(text: $draft.promptTemplate)
                        .font(.body)
                        .frame(minHeight: 120)
                    PromptPlaceholderHelp()
                } header: {
                    Text("本路由发给模型的 user 模板")
                } footer: {
                    Text("若本路由模板整段留空，触发时会回退到上方的「默认旁白请求」模板。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                    if draft.conditions.isEmpty {
                        Text("无条件：等价于「始终」匹配（键盘类规则请勿留空条件，请添加「按键包含」）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(draft.conditions.enumerated()), id: \.offset) { index, _ in
                        conditionRow(index: index)
                    }
                    .onDelete { idx in
                        draft.conditions.remove(atOffsets: idx)
                    }

                    Menu("添加条件") {
                        Button("始终") { draft.conditions.append(.always) }
                        Button("按键包含子串") { draft.conditions.append(.keyboardContains("")) }
                        Button("前台名称包含子串") { draft.conditions.append(.frontAppContains("")) }
                        Button("空闲至少…秒") { draft.conditions.append(.idleAtLeastSeconds(120)) }
                        Button("距上次触发至少…分钟") { draft.conditions.append(.timerElapsedAtLeastMinutes(1)) }
                    }
                } header: {
                    Text("条件（同一路由内为 AND）")
                } footer: {
                    Text("键盘类触发器：至少保留一个「按键包含」且子串非空，否则该路由不会参与匹配。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑旁白路由")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("删除本路由", role: .destructive) {
                        if rule.routes.indices.contains(routeIndex) {
                            rule.routes.remove(at: routeIndex)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if rule.routes.indices.contains(routeIndex) {
                            rule.routes[routeIndex] = draft
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conditionRow(index: Int) -> some View {
        let c = draft.conditions[index]
        switch c {
        case .always:
            HStack {
                Text("始终")
                Spacer()
            }
        case .keyboardContains(let s):
            TextField("按键缓冲需包含（大小写敏感）", text: Binding(
                get: { s },
                set: { draft.conditions[index] = .keyboardContains($0) }
            ))
        case .frontAppContains(let s):
            TextField("前台名称需包含（不区分大小写）", text: Binding(
                get: { s },
                set: { draft.conditions[index] = .frontAppContains($0) }
            ))
        case .idleAtLeastSeconds(let sec):
            Stepper("空闲至少 \(sec) 秒", value: Binding(
                get: { sec },
                set: { draft.conditions[index] = .idleAtLeastSeconds($0) }
            ), in: 0 ... 24 * 3600, step: 10)
        case .timerElapsedAtLeastMinutes(let m):
            Stepper("距上次触发至少 \(m) 分钟", value: Binding(
                get: { m },
                set: { draft.conditions[index] = .timerElapsedAtLeastMinutes($0) }
            ), in: 0 ... 24 * 60, step: 1)
        }
    }
}
