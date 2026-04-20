//
// AgentSettingsTriggerComponents.swift
// 智能体设置：触发器列表行、规则编辑 Sheet、旁白路由编辑（从 AgentSettingsView 拆分）。
//

import AppKit
import SwiftUI

struct TriggerRuleRow: View {
    let rule: AgentTriggerRule
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus
    @EnvironmentObject private var petMenuSettings: SettingsViewModel
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
                    .environmentObject(session)
                    .environmentObject(routeBus)
                    .environmentObject(petMenuSettings)
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
        let slackHint: String = {
            guard settings.triggerSlackNotifyMasterEnabled, r.notifySlack, r.kind != .screenWatch else { return "" }
            return " · Slack"
        }()
        switch r.kind {
        case .timer: return "每 \(r.timerIntervalMinutes) 分钟\(routeHint)\(slackHint)"
        case .randomIdle: return "空闲 ≥\(r.randomIdleSeconds)s，概率 \(Int(r.randomIdleProbability * 100))%\(routeHint)\(slackHint)"
        case .keyboardPattern:
            if r.routes.isEmpty, !r.keyboardPattern.isEmpty { return "模式「\(r.keyboardPattern)」\(slackHint)" }
            return "键盘路由\(routeHint)\(slackHint)"
        case .frontApp:
            if r.routes.isEmpty, !r.frontAppNameContains.isEmpty { return "前台包含「\(r.frontAppNameContains)」\(slackHint)" }
            return "前台路由\(routeHint)\(slackHint)"
        case .screenSnap:
            let perm = ScreenCaptureService.hasScreenRecordingPermission ? "已授权" : "未授权"
            return "间隔≥\(r.screenSnapIntervalMinutes)分·\(perm)\(routeHint)\(slackHint)"
        case .careInteraction: return "饲养面板成功后·旁白\(routeHint)\(slackHint)"
        case .petStatAutomation: return "心情/能量偏低或成长事件·旁白\(routeHint)\(slackHint)"
        case .screenWatch: return "盯屏任务命中旁白"
        }
    }
}

/// 旁白请求模板中占位符的说明（默认模板与单条路由模板共用）。
struct PromptPlaceholderHelp: View {
    var testingMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownInlineText(source: AgentSettingsUICopy.promptPlaceholderIntro(testing: testingMode))
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(AgentSettingsUICopy.promptPlaceholderBullets(testing: testingMode).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        MarkdownInlineText(source: line, font: .caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            MarkdownInlineText(source: AgentSettingsUICopy.promptPlaceholderExample(testing: testingMode))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 截屏 JPEG 滑条：与 `NSBitmapImageRep` 的 `compressionFactor` 同源，数值越大压缩越轻、细节越好、同分辨率下字节越大。
func screenSnapJPEGQualityLiveCaption(_ quality: Double, testing: Bool) -> String {
    AgentSettingsUICopy.screenSnapJPEGQualityBand(quality: quality, testing: testing)
}

struct TriggerRuleEditorSheet: View {
    @State var rule: AgentTriggerRule
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus
    @EnvironmentObject private var petMenuSettings: SettingsViewModel
    @Binding var isPresented: Bool
    @State private var editingRouteIndex: Int?
    @State private var showKeyboardMasterOffOnFinish = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $rule.kind) {
                        ForEach(AgentTriggerKind.allCases.filter { $0 != .screenWatch }) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .disabled(true)
                    Stepper("冷却（秒）: \(Int(rule.cooldownSeconds))", value: $rule.cooldownSeconds, in: 30 ... 3600, step: 30)
                } header: {
                    Text("基本")
                } footer: {
                    MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorBasicFooter(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if rule.kind != .screenWatch {
                    Section {
                        Toggle("此条旁白也发到 Slack", isOn: $rule.notifySlack)
                            .disabled(!settings.triggerSlackNotifyMasterEnabled)
                    } header: {
                        Text("Slack")
                    } footer: {
                        MarkdownInlineText(
                            source: AgentSettingsUICopy.triggerEditorSlackFooter(
                                masterOn: settings.triggerSlackNotifyMasterEnabled,
                                testing: petMenuSettings.testingModeEnabled
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                if rule.kind == .keyboardPattern, !settings.keyboardTriggerMasterEnabled {
                    Section {
                        Label {
                            MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorKeyboardBlockedCallout(testing: petMenuSettings.testingModeEnabled), font: .callout)
                                .foregroundStyle(.primary)
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
                    PromptPlaceholderHelp(testingMode: petMenuSettings.testingModeEnabled)
                } header: {
                    Text("默认旁白请求（无路由命中）")
                } footer: {
                    MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorDefaultTemplateFooter(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                    if rule.routes.isEmpty {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorRoutesEmptyHint(testing: petMenuSettings.testingModeEnabled))
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
                            case .timer, .randomIdle, .screenSnap, .careInteraction, .petStatAutomation, .screenWatch: return [.always]
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
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorRoutesFooterLine1(testing: petMenuSettings.testingModeEnabled))
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorRoutesFooterLine2(testing: petMenuSettings.testingModeEnabled))
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
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorTimerFooter(testing: petMenuSettings.testingModeEnabled))
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
                            ForEach(Array(AgentSettingsUICopy.triggerEditorRandomIdleFooterLines(testing: petMenuSettings.testingModeEnabled).enumerated()), id: \.offset) { _, line in
                                MarkdownInlineText(source: line)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case .keyboardPattern:
                    Section {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorKeyboardCompatInline(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("旧版单一模式串（仅当上方「路由表」为空时生效）", text: $rule.keyboardPattern)
                    } header: {
                        Text("键盘模式（兼容）")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorKeyboardCompatFooterLine1(testing: petMenuSettings.testingModeEnabled))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !settings.keyboardTriggerMasterEnabled {
                                MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorKeyboardCompatFooterMasterOff(testing: petMenuSettings.testingModeEnabled))
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
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorFrontAppFooter(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .screenSnap:
                    Section {
                        HStack {
                            Text("屏幕录制")
                            Spacer()
                            Text(ScreenCaptureService.hasScreenRecordingPermission ? "已授权" : "未授权")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ScreenCaptureService.hasScreenRecordingPermission ? Color.secondary : Color.orange)
                        }
                        Button("打开系统设置…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Stepper("成功旁白最短间隔（分钟）: \(rule.screenSnapIntervalMinutes)", value: $rule.screenSnapIntervalMinutes, in: 5 ... 24 * 60)
                        MarkdownInlineText(source: "与下方「冷却」取**更长**者作为实际上限。", font: .caption2)
                            .foregroundStyle(.tertiary)
                        Toggle("仅宠物窗口可见时自动触发", isOn: $rule.screenSnapOnlyWhenPetVisible)
                        Picker("截图长边上界", selection: $rule.screenSnapMaxEdgePixels) {
                            Text("768 px").tag(768)
                            Text("1024 px").tag(1024)
                            Text("1536 px").tag(1536)
                            Text("2048 px").tag(2048)
                        }
                        HStack {
                            Text("JPEG 质量")
                            Slider(value: $rule.screenSnapJPEGQuality, in: 0.55 ... 0.85, step: 0.02)
                            Text(String(format: "%.2f", rule.screenSnapJPEGQuality))
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                        MarkdownInlineText(
                            source: screenSnapJPEGQualityLiveCaption(rule.screenSnapJPEGQuality, testing: petMenuSettings.testingModeEnabled),
                            font: .caption2
                        )
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("截屏")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(AgentSettingsUICopy.triggerEditorScreenSnapFooterLines(testing: petMenuSettings.testingModeEnabled).enumerated()), id: \.offset) { _, line in
                                MarkdownInlineText(source: line)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case .careInteraction:
                    Section {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorCareInline1(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorCareInline2(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } header: {
                        Text("饲养互动")
                    } footer: {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorCareFooter(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .petStatAutomation:
                    Section {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorPetStatInline1(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorPetStatInline2(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } header: {
                        Text("数值与成长旁白")
                    } footer: {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorPetStatFooter(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .screenWatch:
                    Section {
                        Text("「盯屏任务」由「集成」Tab 配置，不在触发器列表中编辑。此处为占位说明。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("盯屏")
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
                    MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorPerRuleGenFooter(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if petMenuSettings.testingModeEnabled {
                    Section {
                        Button("立即触发当前触发器") {
                            postForceFireTriggerNotification()
                        }
                        .disabled(
                            session.isSending
                                || (rule.kind == .screenSnap
                                    && (!settings.screenSnapTriggerMasterEnabled || !ScreenCaptureService.hasScreenRecordingPermission))
                        )
                    } header: {
                        Text("试跑")
                    } footer: {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorTryRunFooter(testing: petMenuSettings.testingModeEnabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: Binding(
                get: { editingRouteIndex != nil },
                set: { if !$0 { editingRouteIndex = nil } }
            )) {
                if let i = editingRouteIndex, rule.routes.indices.contains(i) {
                    TriggerPromptRouteEditorSheet(rule: $rule, routeIndex: i)
                        .environmentObject(petMenuSettings)
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
                MarkdownInlineText(source: AgentSettingsUICopy.triggerEditorKeyboardSaveAlertMessage(testing: petMenuSettings.testingModeEnabled))
            }
        }
        .frame(minWidth: 400, minHeight: 360)
    }

    private func postForceFireTriggerNotification() {
        guard let data = try? JSONEncoder().encode(rule),
              let json = String(data: data, encoding: .utf8) else { return }
        routeBus.forceFireTriggerRuleJSON(json)
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

struct TriggerPromptRouteEditorSheet: View {
    @Binding var rule: AgentTriggerRule
    let routeIndex: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var petMenuSettings: SettingsViewModel
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
                    PromptPlaceholderHelp(testingMode: petMenuSettings.testingModeEnabled)
                } header: {
                    Text("本路由发给模型的 user 模板")
                } footer: {
                    MarkdownInlineText(source: AgentSettingsUICopy.triggerRouteTemplateFooter(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                    if draft.conditions.isEmpty {
                        MarkdownInlineText(source: AgentSettingsUICopy.triggerRouteUnconditionalHint(testing: petMenuSettings.testingModeEnabled))
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
                    MarkdownInlineText(source: AgentSettingsUICopy.triggerRouteConditionsFooter(testing: petMenuSettings.testingModeEnabled))
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
