//
// ScreenWatchTaskEditorSheet.swift
// 盯屏任务：编辑已有任务（条件、模型兜底、可重复等）。
//

import SwiftUI

struct ScreenWatchTaskEditorSheet: View {
    let taskId: UUID

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var screenWatchTasks: ScreenWatchTaskStore

    @State private var title: String = ""
    @State private var ocrText: String = ""
    @State private var useVision: Bool = false
    @State private var visionHint: String = ""
    @State private var visionCDMinutes: String = "0"
    @State private var visionCDSeconds: String = "15"
    @State private var enableProgress: Bool = false
    @State private var pickedRect: NormalizedRect?
    @State private var deltaString: String = "0.08"
    @State private var repeatAfterHit: Bool = false
    @State private var repeatCDMinutes: String = "0"
    @State private var repeatCDSeconds: String = "60"
    @State private var saveError: String?
    /// Slack 自动创建的任务在本机只允许 OCR + 模型兜底。
    @State private var isSlackAutomatedTask = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务标题", text: $title)
                    TextField("OCR 包含子串（可空）", text: $ocrText)
                } header: {
                    Text("条件")
                }

                Section {
                    Toggle("启用模型兜底（需填写说明）", isOn: $useVision)
                    if useVision {
                        HStack(alignment: .firstTextBaseline) {
                            Text("模型调用冷却")
                            TextField("分", text: $visionCDMinutes)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                            Text("分").font(.caption).foregroundStyle(.secondary)
                            TextField("秒", text: $visionCDSeconds)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                            Text("秒（0…59）").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TextField("兜底条件说明（给模型）", text: $visionHint, axis: .vertical)
                        .lineLimit(2 ... 6)
                } header: {
                    Text("模型兜底")
                }

                Section {
                    if isSlackAutomatedTask {
                        Text("此任务来自 Slack 自动盯屏，仅支持 OCR 与模型兜底，不包含进度条亮度启发式；保存时会移除已误存的进度条件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Toggle("附加：进度条区域亮度启发式", isOn: $enableProgress)
                        if enableProgress {
                            HStack {
                                Button("在主屏框选进度条区域…") {
                                    MainScreenRegionPicker.pickNormalizedRect { rect in
                                        pickedRect = rect
                                    }
                                }
                                if let r = pickedRect {
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
                                TextField("", text: $deltaString, prompt: Text("0.08").foregroundStyle(.tertiary))
                                    .frame(width: 56)
                                    .multilineTextAlignment(.trailing)
                                Text("（0～1）").font(.caption2).foregroundStyle(.tertiary)
                                if let d = Double(deltaString.trimmingCharacters(in: .whitespacesAndNewlines)), !d.isNaN, d >= 0, d <= 1 {
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
                    }
                } header: {
                    Text("进度条启发式")
                }

                Section {
                    Toggle("命中后仍继续盯屏（可重复使用）", isOn: $repeatAfterHit)
                    if repeatAfterHit {
                        HStack(alignment: .firstTextBaseline) {
                            Text("再次命中最短间隔")
                            TextField("分", text: $repeatCDMinutes)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                            Text("分").font(.caption).foregroundStyle(.secondary)
                            TextField("秒", text: $repeatCDSeconds)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                            Text("秒（0…59）").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("两次旁白/命中之间的最短等待，避免条件一直为真时连续刷屏。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text("重复")
                }

                if let saveError {
                    Section {
                        Text(saveError).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isSlackAutomatedTask ? "编辑盯屏任务（Slack）" : "编辑盯屏任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
        .onAppear {
            loadFromStore()
        }
    }

    private func loadFromStore() {
        guard let t = screenWatchTasks.tasks.first(where: { $0.id == taskId }) else {
            dismiss()
            return
        }
        isSlackAutomatedTask = (t.creationSource == .slackAutomated)
        title = t.title
        ocrText = t.firstOCRSubstring
        useVision = t.useVisionFallback
        visionHint = t.visionUserHint
        let vTotal = Int(t.visionFallbackCooldownSeconds.rounded())
        visionCDMinutes = String(vTotal / 60)
        visionCDSeconds = String(vTotal % 60)
        if isSlackAutomatedTask {
            enableProgress = false
            pickedRect = nil
            deltaString = "0.08"
        } else {
            enableProgress = t.firstProgressBarCondition != nil
            pickedRect = t.firstProgressBarCondition?.rect
            if let d = t.firstProgressBarCondition?.deltaThreshold {
                deltaString = String(format: "%.4g", d)
            } else {
                deltaString = "0.08"
            }
        }
        repeatAfterHit = t.repeatAfterHit
        let rTotal = Int(t.repeatCooldownSeconds.rounded())
        repeatCDMinutes = String(rTotal / 60)
        repeatCDSeconds = String(rTotal % 60)
    }

    private func save() {
        saveError = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            saveError = "请填写任务标题。"
            return
        }
        if !isSlackAutomatedTask, enableProgress, pickedRect == nil {
            saveError = "已打开进度条启发式时，请在主屏框选区域。"
            return
        }
        if useVision, visionHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveError = "启用模型兜底时请填写说明。"
            return
        }

        var conditions: [ScreenWatchCondition] = []
        let ocr = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ocr.isEmpty {
            conditions.append(.ocrContains(text: ocr, caseInsensitive: true))
        }
        if !isSlackAutomatedTask, enableProgress, let rect = pickedRect {
            let delta = Self.clampedProgressDelta(deltaString)
            conditions.append(.progressBarFilled(rect: rect, deltaThreshold: delta))
        }
        if conditions.isEmpty, !useVision {
            saveError = "请至少配置 OCR、进度条启发式之一，或启用模型兜底并填写说明。"
            return
        }

        guard var existing = screenWatchTasks.tasks.first(where: { $0.id == taskId }) else {
            saveError = "任务已不存在。"
            dismiss()
            return
        }

        let visionCooldown = Self.cooldownSecondsFromParts(minutes: visionCDMinutes, seconds: visionCDSeconds, minTotal: 1)
        let repeatCooldown = Self.cooldownSecondsFromParts(minutes: repeatCDMinutes, seconds: repeatCDSeconds, minTotal: 5)

        existing.title = trimmedTitle
        existing.conditions = conditions
        existing.useVisionFallback = useVision
        existing.visionUserHint = visionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.visionFallbackCooldownSeconds = visionCooldown
        existing.repeatAfterHit = repeatAfterHit
        existing.repeatCooldownSeconds = repeatCooldown

        screenWatchTasks.upsert(existing)
        dismiss()
    }

    private static func clampedProgressDelta(_ string: String) -> Double {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Double(t), !v.isNaN, !v.isInfinite else { return 0.08 }
        return min(1, max(0, v))
    }

    /// 分 + 秒（秒 0…59）→ 总秒数，再按 `minTotal`…86400 钳制。
    private static func cooldownSecondsFromParts(minutes: String, seconds: String, minTotal: Int) -> Double {
        let m = Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let sRaw = Int(seconds.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let mclamped = max(0, m)
        let sclamped = min(59, max(0, sRaw))
        let total = mclamped * 60 + sclamped
        return Double(max(minTotal, min(86_400, total)))
    }
}
