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
            Section("服务端") {
                TextField("Base URL", text: $settings.baseURL)
                TextField("模型 id", text: $settings.model)
            }
            Section("API Key（钥匙串）") {
                SecureField("粘贴 DeepSeek API Key", text: $apiKeyDraft)
                HStack {
                    Button("保存到钥匙串") {
                        do {
                            try KeychainStore.saveAPIKey(apiKeyDraft)
                            keychainMessage = "已保存。"
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
            }
            Section("生成参数") {
                HStack {
                    Text("温度")
                    Slider(value: $settings.temperature, in: 0 ... 1.5, step: 0.05)
                    Text(String(format: "%.2f", settings.temperature))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                Stepper("max_tokens：\(settings.maxTokens)", value: $settings.maxTokens, in: 64 ... 4096, step: 64)
            }
            Section {
                Button("清空当前对话") {
                    session.clearSession()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var personalityTab: some View {
        Form {
            Section("系统提示（人格）") {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 200)
            }
        }
        .formStyle(.grouped)
    }

    private var triggersTab: some View {
        Form {
            Section {
                Text("每条规则有独立冷却；定时与随机空闲适合日常使用。键盘与前台应用属于进阶能力，请谨慎开启。")
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
            Section("请求增强（高风险）") {
                Toggle("在对话请求中附带键入摘要", isOn: $settings.attachKeySummary)
                Text("依赖桌镜的键位标签摘要，可能暴露你正在输入的大致内容；默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("进阶触发总开关") {
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
                Section("基本") {
                    Picker("类型", selection: $rule.kind) {
                        ForEach(AgentTriggerKind.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .disabled(true)
                    Stepper("冷却（秒）: \(Int(rule.cooldownSeconds))", value: $rule.cooldownSeconds, in: 30 ... 3600, step: 30)
                }
                switch rule.kind {
                case .timer:
                    Section("定时") {
                        Stepper("间隔（分钟）: \(rule.timerIntervalMinutes)", value: $rule.timerIntervalMinutes, in: 1 ... 24 * 60)
                    }
                case .randomIdle:
                    Section("随机空闲") {
                        Stepper("空闲秒数: \(rule.randomIdleSeconds)", value: $rule.randomIdleSeconds, in: 10 ... 3600, step: 10)
                        HStack {
                            Text("触发概率")
                            Slider(value: $rule.randomIdleProbability, in: 0.01 ... 0.5, step: 0.01)
                            Text(String(format: "%.0f%%", rule.randomIdleProbability * 100))
                                .font(.caption.monospacedDigit())
                        }
                    }
                case .keyboardPattern:
                    Section("键盘模式") {
                        Text("仅匹配模式串（最近按键缓冲），不保存全文日志。需打开「隐私」中的总开关。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("要匹配的子串", text: $rule.keyboardPattern)
                    }
                case .frontApp:
                    Section("前台应用") {
                        TextField("应用名包含（本地化名称子串）", text: $rule.frontAppNameContains)
                    }
                case .screenSnap:
                    Section("截屏") {
                        Text("当前版本不会触发；占位以便后续接入 ScreenCaptureKit 等能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
