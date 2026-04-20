//
// IntegrationsTabView.swift
// 智能体设置 ·「集成」Tab：盯屏任务与事件。
//

import SwiftUI

private struct ScreenWatchEditorPresentation: Identifiable, Equatable {
    let id: UUID
}

struct IntegrationsTabView: View {
    @EnvironmentObject private var multimodalLimits: MultimodalAttachmentLimitsStore
    @EnvironmentObject private var screenWatchTasks: ScreenWatchTaskStore
    @EnvironmentObject private var screenWatchEvents: ScreenWatchEventStore
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

    @State private var watchNewTitle: String = ""
    @State private var watchOCRText: String = ""
    @State private var watchVisionHint: String = ""
    @State private var watchUseVision = false
    @State private var watchVisionCDMinutes: String = "0"
    @State private var watchVisionCDSeconds: String = "15"
    @State private var watchEnableProgress = false
    @State private var watchPickedProgressRect: NormalizedRect?
    @State private var watchDelta: String = "0.08"
    @State private var watchRepeatAfterHit = false
    @State private var watchRepeatCDMinutes: String = "0"
    @State private var watchRepeatCDSeconds: String = "60"
    @State private var screenWatchEditorPresentation: ScreenWatchEditorPresentation?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownInlineText(source: AgentSettingsUICopy.integrationsMultimodalIntro(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("单张图片最大：\(String(format: "%.1f", Double(multimodalLimits.maxImageAttachmentBytes) / 1_048_576)) MB")
                    Slider(value: Binding(
                        get: { Double(multimodalLimits.maxImageAttachmentBytes) / 1_048_576 },
                        set: {
                            multimodalLimits.maxImageAttachmentBytes = Int($0 * 1_048_576)
                            multimodalLimits.clampAll()
                        }
                    ), in: 0.5 ... 25)
                    Text("单个非图片文件最大：\(String(format: "%.1f", Double(multimodalLimits.maxFileAttachmentBytes) / 1_048_576)) MB")
                    Slider(value: Binding(
                        get: { Double(multimodalLimits.maxFileAttachmentBytes) / 1_048_576 },
                        set: {
                            multimodalLimits.maxFileAttachmentBytes = Int($0 * 1_048_576)
                            multimodalLimits.clampAll()
                        }
                    ), in: (1.0 / 1024.0) ... 20)
                    Text("PDF / 文本抽取 UTF-8 上限：\(multimodalLimits.maxTextExtractBytes / 1024) KB")
                    Slider(value: Binding(
                        get: { Double(multimodalLimits.maxTextExtractBytes) / 1024 },
                        set: {
                            multimodalLimits.maxTextExtractBytes = Int($0 * 1024)
                            multimodalLimits.clampAll()
                        }
                    ), in: 4 ... 2048)
                }
            } header: {
                Text("多模态附件限额")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.integrationsMultimodalFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                MarkdownInlineText(source: AgentSettingsUICopy.integrationsRemoteClickBody(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if petMenuSettings.testingModeEnabled {
                    MarkdownInlineText(source: AgentSettingsUICopy.integrationsRemoteClickSelfTest(testing: true))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Slack 远程点屏")
            }

            Section {
                MarkdownInlineText(source: AgentSettingsUICopy.integrationsWatchTasksIntro(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("新任务标题", text: $watchNewTitle)
                TextField("OCR 包含子串（可空）", text: $watchOCRText)
                Toggle("启用模型兜底（需填写说明）", isOn: $watchUseVision)
                if watchUseVision {
                    HStack(alignment: .firstTextBaseline) {
                        Text("模型调用冷却")
                        TextField("分", text: $watchVisionCDMinutes)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                        Text("分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("秒", text: $watchVisionCDSeconds)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                        Text("秒（0…59）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    MarkdownInlineText(source: AgentSettingsUICopy.integrationsVisionCooldownClockHint(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                TextField("兜底条件说明（给模型）", text: $watchVisionHint, axis: .vertical)
                    .lineLimit(2 ... 6)
                Toggle("附加：进度条区域亮度启发式", isOn: $watchEnableProgress)
                if watchEnableProgress {
                    HStack {
                        Button("在主屏框选进度条区域…") {
                            MainScreenRegionPicker.pickNormalizedRect { rect in
                                watchPickedProgressRect = rect
                            }
                        }
                        if let r = watchPickedProgressRect {
                            Text(String(format: "已选：x=%.2f y=%.2f w=%.2f h=%.2f", r.x, r.y, r.width, r.height))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("尚未框选")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    MarkdownInlineText(source: AgentSettingsUICopy.watchProgressBarAlgorithmPrimary(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .firstTextBaseline) {
                        Text("最大允许左右亮度差")
                        TextField("", text: $watchDelta, prompt: Text("0.08").foregroundStyle(.tertiary))
                            .frame(width: 56)
                            .multilineTextAlignment(.trailing)
                        Text("（0～1）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let d = Double(watchDelta.trimmingCharacters(in: .whitespacesAndNewlines)), !d.isNaN, d >= 0, d <= 1 {
                            Text("即 |左−右| ≤ \(Int((d * 100).rounded())) 个百分点")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    MarkdownInlineText(source: AgentSettingsUICopy.watchProgressBarAlgorithmSecondary(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle("命中后仍继续盯屏（可重复使用）", isOn: $watchRepeatAfterHit)
                if watchRepeatAfterHit {
                    HStack(alignment: .firstTextBaseline) {
                        Text("再次命中最短间隔")
                        TextField("分", text: $watchRepeatCDMinutes)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                        Text("分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("秒", text: $watchRepeatCDSeconds)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                        Text("秒（0…59）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    MarkdownInlineText(source: AgentSettingsUICopy.integrationsWatchRepeatCooldownHint(testing: petMenuSettings.testingModeEnabled))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("添加盯屏任务") {
                    addScreenWatchTaskFromForm()
                }
                ForEach(screenWatchTasks.tasks) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(t.title).font(.headline)
                                    if t.creationSource == .slackAutomated {
                                        Text("Slack")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.quaternary.opacity(0.6), in: Capsule())
                                            .help("该任务由 Slack 里让猫猫盯屏自动创建；仅 OCR / 模型兜底，不含进度条亮度启发式。")
                                    }
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(watchTaskBaseState(t))
                                        .foregroundStyle(.secondary)
                                    if t.firstProgressBarCondition != nil, t.isEnabled, t.creationSource != .slackAutomated {
                                        Text(watchProgressHeuristicArmedLabel(t))
                                            .foregroundStyle(watchProgressHeuristicArmedColor(t))
                                            .help("进度条启发式：需先观察到左右平均亮度差足够大，「够均匀」判定才会生效。")
                                    }
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                    Text(watchTaskRepeatPart(t))
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.caption2)
                            }
                            Spacer()
                            Button("编辑") {
                                screenWatchEditorPresentation = ScreenWatchEditorPresentation(id: t.id)
                            }
                            Toggle("", isOn: screenWatchEnabledBinding(for: t))
                                .labelsHidden()
                            Button("删除", role: .destructive) {
                                screenWatchTasks.remove(id: t.id)
                            }
                        }
                        if t.useVisionFallback {
                            HStack(alignment: .firstTextBaseline) {
                                Text("模型调用冷却")
                                    .font(.caption)
                                TextField("分", text: visionCooldownMinutesBinding(for: t.id))
                                    .frame(width: 44)
                                    .multilineTextAlignment(.trailing)
                                    .font(.caption)
                                Text("分")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                TextField("秒", text: visionCooldownSecondsBinding(for: t.id))
                                    .frame(width: 44)
                                    .multilineTextAlignment(.trailing)
                                    .font(.caption)
                                Text("秒（0…59）")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("盯屏任务")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.integrationsWatchTasksFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                if screenWatchEvents.events.isEmpty {
                    Text("暂无盯屏事件")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(screenWatchEvents.events.prefix(40)) { ev in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(ev.kind.rawValue)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(shortDate(ev.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(ev.taskTitle).font(.caption)
                            Text(ev.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Button("清空盯屏事件列表", role: .destructive) {
                    screenWatchEvents.clear()
                }
            } header: {
                Text("盯屏事件")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $screenWatchEditorPresentation) { item in
            ScreenWatchTaskEditorSheet(taskId: item.id)
                .environmentObject(screenWatchTasks)
                .environmentObject(petMenuSettings)
                .frame(minWidth: 480, minHeight: 560)
        }
    }

    private func watchTaskBaseState(_ t: ScreenWatchTask) -> String {
        t.isEnabled ? "运行中" : "已停用/已命中"
    }

    private func watchTaskRepeatPart(_ t: ScreenWatchTask) -> String {
        if t.repeatAfterHit {
            let sec = Int(t.repeatCooldownSeconds.rounded())
            return "可重复 · 再次命中≥\(sec)秒"
        }
        return "单次"
    }

    private func watchProgressHeuristicArmedLabel(_ t: ScreenWatchTask) -> String {
        let armed = screenWatchTasks.progressHeuristicArmedByTaskId[t.id] ?? false
        return armed ? "· 已见证不对称" : "· 待见证不对称"
    }

    private func watchProgressHeuristicArmedColor(_ t: ScreenWatchTask) -> Color {
        (screenWatchTasks.progressHeuristicArmedByTaskId[t.id] ?? false) ? .secondary : .orange
    }

    private static func clampedProgressDeltaThreshold(string: String) -> Double {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Double(t), !v.isNaN, !v.isInfinite else { return 0.08 }
        return min(1, max(0, v))
    }

    private static func visionCooldownTotalSeconds(minutesString: String, secondsString: String) -> Double {
        let m = Int(minutesString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let sRaw = Int(secondsString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let mclamped = max(0, m)
        let sclamped = min(59, max(0, sRaw))
        let total = mclamped * 60 + sclamped
        return Double(max(1, min(86_400, total)))
    }

    private static func repeatCooldownTotalSeconds(minutesString: String, secondsString: String) -> Double {
        let m = Int(minutesString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let sRaw = Int(secondsString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let mclamped = max(0, m)
        let sclamped = min(59, max(0, sRaw))
        let total = mclamped * 60 + sclamped
        return Double(max(5, min(86_400, total)))
    }

    private func visionCooldownMinutesBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let t = screenWatchTasks.tasks.first(where: { $0.id == taskId }) else { return "0" }
                let total = Int(t.visionFallbackCooldownSeconds.rounded())
                return String(total / 60)
            },
            set: { new in
                guard var t = screenWatchTasks.tasks.first(where: { $0.id == taskId }) else { return }
                let m = max(0, Int(new.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
                let s = Int(t.visionFallbackCooldownSeconds.rounded()) % 60
                let newTotal = max(1, min(86_400, m * 60 + s))
                t.visionFallbackCooldownSeconds = Double(newTotal)
                screenWatchTasks.upsert(t)
            }
        )
    }

    private func visionCooldownSecondsBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let t = screenWatchTasks.tasks.first(where: { $0.id == taskId }) else { return "0" }
                let total = Int(t.visionFallbackCooldownSeconds.rounded())
                return String(total % 60)
            },
            set: { new in
                guard var t = screenWatchTasks.tasks.first(where: { $0.id == taskId }) else { return }
                let m = Int(t.visionFallbackCooldownSeconds.rounded()) / 60
                let s = min(59, max(0, Int(new.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
                let newTotal = max(1, min(86_400, m * 60 + s))
                t.visionFallbackCooldownSeconds = Double(newTotal)
                screenWatchTasks.upsert(t)
            }
        )
    }

    private func screenWatchEnabledBinding(for task: ScreenWatchTask) -> Binding<Bool> {
        Binding(
            get: { screenWatchTasks.tasks.first { $0.id == task.id }?.isEnabled ?? false },
            set: { v in
                guard var t = screenWatchTasks.tasks.first(where: { $0.id == task.id }) else { return }
                t.isEnabled = v
                screenWatchTasks.upsert(t)
            }
        )
    }

    private func addScreenWatchTaskFromForm() {
        let title = watchNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let ocr = watchOCRText.trimmingCharacters(in: .whitespacesAndNewlines)
        var conditions: [ScreenWatchCondition] = []
        if !ocr.isEmpty {
            conditions.append(.ocrContains(text: ocr, caseInsensitive: true))
        }
        if watchEnableProgress {
            guard let rect = watchPickedProgressRect else { return }
            let delta = Self.clampedProgressDeltaThreshold(string: watchDelta)
            conditions.append(.progressBarFilled(rect: rect, deltaThreshold: delta))
        }
        if conditions.isEmpty, !watchUseVision {
            return
        }
        if watchUseVision {
            let h = watchVisionHint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !h.isEmpty else { return }
        }
        let hint = watchVisionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let visionCooldown = Self.visionCooldownTotalSeconds(
            minutesString: watchVisionCDMinutes,
            secondsString: watchVisionCDSeconds
        )
        let repeatCooldown = Self.repeatCooldownTotalSeconds(
            minutesString: watchRepeatCDMinutes,
            secondsString: watchRepeatCDSeconds
        )
        let task = ScreenWatchTask(
            title: title,
            isEnabled: true,
            sampleIntervalSeconds: 3,
            conditions: conditions,
            useVisionFallback: watchUseVision,
            visionUserHint: hint,
            visionFallbackCooldownSeconds: visionCooldown,
            repeatAfterHit: watchRepeatAfterHit,
            repeatCooldownSeconds: repeatCooldown
        )
        screenWatchTasks.upsert(task)
        watchNewTitle = ""
        watchOCRText = ""
        watchPickedProgressRect = nil
        watchRepeatAfterHit = false
        watchRepeatCDMinutes = "0"
        watchRepeatCDSeconds = "60"
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}
