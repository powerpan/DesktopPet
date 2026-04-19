//
// ScreenWatchRunner.swift
// 盯屏任务轮询：本地 OCR / 亮度启发式优先，可选多模态模型 YES/NO 兜底。
//

import Foundation
import SwiftUI

@MainActor
final class ScreenWatchRunner: ObservableObject {
    private let tasks: ScreenWatchTaskStore
    private let events: ScreenWatchEventStore
    private var loopTask: Task<Void, Never>?
    private var lastSampleAt: [UUID: Date] = [:]
    /// 模型兜底（多模态）两次调用之间的最短间隔，按任务分别节流。
    private var lastVisionCallAt: [UUID: Date] = [:]
    /// 进度条启发式：是否已观察到「左右明显不对称」（避免 0% 均匀轨误判）。
    private var progressBarHeuristicArmed: [UUID: Bool] = [:]
    /// 上一轮各任务的 `isEnabled`，用于检测「重新启用」并重置武装。
    private var lastTaskWatchEnabled: [UUID: Bool] = [:]
    /// 可重复模式下上次命中时间，用于 `repeatCooldownSeconds` 防抖。
    private var lastHitAt: [UUID: Date] = [:]
    private weak var agentClient: AgentClient?
    private weak var agentSettings: AgentSettingsStore?
    private var onHit: ((ScreenWatchTask, String, ScreenWatchHitNarrativeKind) -> Void)?

    init(tasks: ScreenWatchTaskStore, events: ScreenWatchEventStore) {
        self.tasks = tasks
        self.events = events
    }

    func start(
        agentClient: AgentClient,
        agentSettings: AgentSettingsStore,
        onHit: @escaping (ScreenWatchTask, String, ScreenWatchHitNarrativeKind) -> Void
    ) {
        self.agentClient = agentClient
        self.agentSettings = agentSettings
        self.onHit = onHit
        progressBarHeuristicArmed.removeAll(keepingCapacity: true)
        lastTaskWatchEnabled.removeAll(keepingCapacity: true)
        lastHitAt.removeAll(keepingCapacity: true)
        tasks.clearAllProgressHeuristicArmedSnapshots()
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        agentClient = nil
        agentSettings = nil
        onHit = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { break }
            await evaluateAll()
        }
    }

    private func evaluateAll() async {
        guard ScreenCaptureService.hasScreenRecordingPermission else { return }
        let all = tasks.tasks
        for t in all {
            let was = lastTaskWatchEnabled[t.id] ?? false
            if !t.isEnabled {
                progressBarHeuristicArmed.removeValue(forKey: t.id)
                tasks.removeProgressHeuristicArmed(taskId: t.id)
            } else if !was {
                progressBarHeuristicArmed[t.id] = false
                lastHitAt[t.id] = nil
                if Self.taskHasProgressHeuristic(t) {
                    tasks.setProgressHeuristicArmed(taskId: t.id, isArmed: false)
                }
            }
            lastTaskWatchEnabled[t.id] = t.isEnabled
        }
        for task in all where task.isEnabled {
            let last = lastSampleAt[task.id] ?? .distantPast
            if Date().timeIntervalSince(last) < task.sampleIntervalSeconds { continue }
            lastSampleAt[task.id] = Date()
            await evaluateOne(task)
        }
    }

    private func evaluateOne(_ task: ScreenWatchTask) async {
        if task.repeatAfterHit, let last = lastHitAt[task.id] {
            let cd = min(86_400, max(5, task.repeatCooldownSeconds))
            if Date().timeIntervalSince(last) < cd { return }
        }

        let jpeg: Data
        do {
            // 略提高分辨率与 JPEG 质量，减轻小字号中文（如「进度条」）在缩放后的漏检；模型兜底仍用同一帧。
            jpeg = try await ScreenCaptureService.captureMainDisplayJPEG(maxEdge: 1536, jpegQuality: 0.72)
        } catch {
            events.append(ScreenWatchEvent(taskId: task.id, taskTitle: task.title, kind: .error, detail: error.localizedDescription))
            return
        }

        let conds = Self.conditionsEvaluatedLocally(for: task)
        let localHit: Bool
        if conds.isEmpty {
            localHit = false
            syncProgressHeuristicArmStateToStore(for: task)
        } else {
            var okAll = true
            for cond in conds {
                switch cond {
                case let .ocrContains(text, ci):
                    let ok = await ScreenWatchOCRDetector.imageContains(jpegData: jpeg, substring: text, caseInsensitive: ci)
                    if !ok { okAll = false }
                case let .progressBarFilled(rect, threshold):
                    var armed = progressBarHeuristicArmed[task.id] ?? false
                    let ok = ScreenWatchProgressHeuristic.progressLikelyFilled(
                        jpegData: jpeg,
                        rect: rect,
                        maxLuminanceDelta: threshold,
                        armed: &armed
                    )
                    progressBarHeuristicArmed[task.id] = armed
                    if !ok { okAll = false }
                }
            }
            localHit = okAll
            syncProgressHeuristicArmStateToStore(for: task)
        }

        if localHit {
            fireHit(task: task, detail: "本地规则已满足（OCR/亮度）。", narrativeKind: .localHeuristic)
            return
        }

        guard task.useVisionFallback, let client = agentClient, let settings = agentSettings else { return }
        let hint = task.visionUserHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hint.isEmpty else { return }
        let cooldown = min(86_400, max(1, task.visionFallbackCooldownSeconds))
        let sinceVision = Date().timeIntervalSince(lastVisionCallAt[task.id] ?? .distantPast)
        if sinceVision < cooldown { return }
        let key = KeychainStore.readAPIKey(forProvider: settings.activeAPIProvider)
        let sys = "你只回答一个大写单词：YES 或 NO。不要解释。"
        let userText = """
        用户让桌宠盯着屏幕，判断条件是否满足。请仅根据截图回答 YES 或 NO。
        条件说明：\(hint)
        """
        let parts: [AgentAPIChatContentPart] = [.text(userText), .imageJPEG(jpeg)]
        let userMsg = AgentAPIChatUserMessage(parts: parts)
        lastVisionCallAt[task.id] = Date()
        do {
            let ans = try await client.completeChat(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: key,
                systemPrompt: sys,
                userMessages: [userMsg],
                temperature: 0,
                maxTokens: 8,
                extendedTimeout: true
            )
            let u = ans.uppercased()
            if u.contains("YES") {
                fireHit(task: task, detail: "模型兜底判定：YES（\(ans.prefix(80))）", narrativeKind: .visionFallback)
            }
        } catch {
            events.append(ScreenWatchEvent(taskId: task.id, taskTitle: task.title, kind: .error, detail: "模型兜底失败：\(error.localizedDescription)"))
        }
    }

    private func fireHit(task: ScreenWatchTask, detail: String, narrativeKind: ScreenWatchHitNarrativeKind) {
        let preHitSnapshot = task
        var t = task
        if !t.repeatAfterHit {
            t.isEnabled = false
        }
        tasks.upsert(t)
        events.append(ScreenWatchEvent(taskId: task.id, taskTitle: task.title, kind: .hit, detail: detail))
        lastHitAt[task.id] = Date()
        if t.repeatAfterHit {
            progressBarHeuristicArmed[task.id] = false
            syncProgressHeuristicArmStateToStore(for: t)
        } else {
            progressBarHeuristicArmed.removeValue(forKey: task.id)
            tasks.removeProgressHeuristicArmed(taskId: task.id)
        }
        onHit?(preHitSnapshot, detail, narrativeKind)
    }

    /// Slack 自动盯屏仅 OCR / 模型兜底：本地评估时忽略进度条亮度条件（含历史误存数据）。
    private static func conditionsEvaluatedLocally(for task: ScreenWatchTask) -> [ScreenWatchCondition] {
        if task.creationSource == .slackAutomated {
            return task.conditions.filter {
                if case .ocrContains = $0 { return true }
                return false
            }
        }
        return task.conditions
    }

    private static func taskHasProgressHeuristic(_ task: ScreenWatchTask) -> Bool {
        guard task.creationSource != .slackAutomated else { return false }
        return task.conditions.contains {
            if case .progressBarFilled = $0 { return true }
            return false
        }
    }

    private func syncProgressHeuristicArmStateToStore(for task: ScreenWatchTask) {
        if Self.taskHasProgressHeuristic(task) {
            tasks.setProgressHeuristicArmed(taskId: task.id, isArmed: progressBarHeuristicArmed[task.id] ?? false)
        } else {
            tasks.removeProgressHeuristicArmed(taskId: task.id)
        }
    }
}
