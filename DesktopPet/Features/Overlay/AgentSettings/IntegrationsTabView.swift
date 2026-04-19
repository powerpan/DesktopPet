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
                    Text("同时作用于对话面板「+」上传与 Slack 入站附件；超出限额时不会在 Slack 调用模型，并在对应线程回复原因。")
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
                Text("Slack 侧需为 Bot 配置 **files:read**（及可访问 files.slack.com 私有下载链接），否则无法下载频道内图片/文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("在监控频道发送 **`!pet click`** / **`!pet 点屏`**，或整句以中文触发词开头（例如 **远程点屏**、**远程点击**、**帮点一下屏幕**、**猫猫远程点屏**、**屏幕远程点击** 等；关键词后请接空格、逗号或句号，不要写成「远程点屏谢谢」这种紧接其它汉字，以免误触）。应用会截取主屏并上传带 0–100 标尺的坐标图（需 **屏幕录制** + Bot **files:write**；上传失败时仍会提示你用文字回复坐标）。在**同一线程**回复一次坐标，例如 **`50,50`** 或 **`x=0.5 y=0.5`**（支持 0–100 或 0–1；越界会提示错误）。**执行点击需要「辅助功能」权限**（系统设置 → 隐私与安全性 → 辅助功能）。单次会话仅执行一次左键，成功后结束；约 5 分钟超时。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("端到端自测建议：① 发 `!pet click` 见线程内坐标图；② 回 `50,50` 应点在主屏视觉中心附近；③ 回 `x=120` 类越界应报错且不点击；④ 关闭辅助功能后应仅回帖提示授权。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Slack 远程点屏")
            }

            Section {
                Text("需已授予「屏幕录制」权限。本地 OCR / 进度条亮度启发式优先；可选多模态模型 YES/NO 兜底（消耗 API）。")
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
                    Text("秒为钟表意义上的 0…59；总间隔最长 24 小时。仅当本地条件未全部满足时才会请求模型。")
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
                    Text("把整条进度条框进矩形。算法取该区域最左 1/5 与最右 1/5 的平均亮度（约 0=黑、1=白）。常见「从左往右填满」时：未完成往往左右一边更亮、差较大；走完后整条颜色接近一致，差会变小。当「左右平均亮度差的绝对值」≤ 下方阈值时，判定为接近/已完成。")
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
                    Text("默认 0.08：左右平均亮度最多相差约 8 个百分点即视为「够均匀」。阈值越大越容易满足（更早触发）；越小越严格。为避免 0% 时整条底轨已很均匀而误判，会先要求在本任务运行期间出现过一次「左右明显不对称」，再接受「够均匀」；若从接近 100% 才开始盯屏，可能一直不满足，请配合 OCR 或模型兜底。")
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
                    Text("可重复时两次命中之间的最短等待，避免条件一直为真时连续旁白。")
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
                Text("启用进度条启发式时，请在主屏拖拽框选区域（Esc 取消）；无需手填数字。模型兜底在本地未命中时才会调用。已添加的任务可点「编辑」修改条件、兜底说明、是否重复使用及间隔。")
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
