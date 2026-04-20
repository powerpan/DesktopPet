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
                Text("· {statContext} — 仅「数值与成长旁白」：心情/能量偏低或成长随机事件时，由应用填入结构化说明；未触发时为空。")
                Text("· {screenCaptureMeta} — 仅「截屏」类型：应用填入时间、前台应用名、缩放与是否降级为纯文字等摘要；勿在模板中手写该占位符以外的机密内容。")
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

/// 截屏 JPEG 滑条：与 `NSBitmapImageRep` 的 `compressionFactor` 同源，数值越大压缩越轻、细节越好、同分辨率下字节越大。
func screenSnapJPEGQualityLiveCaption(_ quality: Double) -> String {
    let v = min(0.85, max(0.55, quality))
    let band: String
    if v < 0.62 {
        band = "压缩偏强：上传更快、更省流量，界面小字与细边更容易出现马赛克。"
    } else if v < 0.72 {
        band = "折中：体积与清晰度较均衡，多数截屏旁白够用。"
    } else if v < 0.80 {
        band = "偏清晰：文字与边缘更利落，请求体与耗时通常增加。"
    } else {
        band = "接近上限：尽量保细节，JPEG 与 Base64 请求体会明显变大。"
    }
    return "当前 \(String(format: "%.2f", v))（约 \(String(format: "%.0f", v * 100))% 强度）— \(band)"
}

struct TriggerRuleEditorSheet: View {
    @State var rule: AgentTriggerRule
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus
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
                    Text("冷却：两次触发之间的最短间隔（秒）。触发一次后会进入冷却，期间即使条件仍满足也不会再请求。")
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
                        Text(
                            settings.triggerSlackNotifyMasterEnabled
                                ? "开启后，本条触发产生的旁白除气泡外，会发到「连接」里配置的 Slack 监控频道（需 Bot Token 与频道 ID）。"
                                : "请先在「触发器」列表顶部的 Slack 区域打开「触发旁白也推送到 Slack」总开关，再为各条规则单独开启。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
                            Text("同一段键鼠静止期内：每条「随机空闲」规则在成功旁白一次后会暂停，直到你再次键鼠活动后才会重新参与随机判定（仍须满足冷却与最小间隔）。")
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
                        Text("与下方「冷却」取**更长**者作为实际上限。")
                            .font(.caption2)
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
                        Text(screenSnapJPEGQualityLiveCaption(rule.screenSnapJPEGQuality))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        Text("截屏")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("冷却下限请使用上方「基本」中的「冷却（秒）」；与「成功旁白最短间隔」取**更长**者作为实际上限。")
                            Text("JPEG 质量系数（0.55～0.85）：与 macOS 编码 JPEG 时的 compressionFactor 一致，表示有损压缩的轻重，不是分辨率。系数越高，同一截屏下画质越好、文件越大、上传越慢、API 请求体越大；越低则相反。与上方「长边上界」共同影响模型能否看清屏上小字。")
                            Text("自动触发需打开「隐私」中的截屏档位（截取主屏或截取副屏），并授予屏幕录制。所选显示器经 ScreenCaptureKit 抓取后按「长边上界」缩放再 JPEG 编码（最大 2048px），仅在内存中上传；长边越大越利于认字，但请求体与耗时通常也会增加。")
                            Text("若模型不支持图像，应用会在收到 HTTP 400 时自动改为纯文字再请求一次。")
                        }
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
                case .petStatAutomation:
                    Section {
                        Text("由「陪伴 → 成长」中的「数值旁白自动化」在心情/能量低于阈值或发生成长随机事件时触发。应用将说明写入 {statContext}；模型失败时会用本地兜底短句。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("成长 Tab 里另有「最短间隔」分钟数，与上方「冷却」共同限制频率；仅**第一条已启用**的本类型规则会收到事件。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } header: {
                        Text("数值与成长旁白")
                    } footer: {
                        Text("可与 {extra}、{matchedCondition} 等占位符组合；建议语气偏撒娇、诉苦，一两句即可。")
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
                    Text("关闭开关时使用「触发器」Tab 的默认温度与 max_tokens。从气泡进入长对话后，发送消息仍使用「连接」Tab 的设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
                    Text("使用当前编辑页中的表单内容（含未点「完成」的修改）向模型请求一次旁白；成功后会出现旁白气泡并写入「旁白历史」与「发给模型的请求」。截屏类在成功收到模型回复后才更新「上次触发」。路由会先按当前环境匹配；若无命中则回退第一条启用路由。截屏试跑需打开隐私总开关并已授予屏幕录制；正在发送时按钮不可用。")
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
