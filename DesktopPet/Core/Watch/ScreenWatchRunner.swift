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
    private weak var agentClient: AgentClient?
    private weak var agentSettings: AgentSettingsStore?
    private var onHit: ((String, String) -> Void)?

    init(tasks: ScreenWatchTaskStore, events: ScreenWatchEventStore) {
        self.tasks = tasks
        self.events = events
    }

    func start(
        agentClient: AgentClient,
        agentSettings: AgentSettingsStore,
        onHit: @escaping (String, String) -> Void
    ) {
        self.agentClient = agentClient
        self.agentSettings = agentSettings
        self.onHit = onHit
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
        for task in tasks.tasks where task.isEnabled {
            let last = lastSampleAt[task.id] ?? .distantPast
            if Date().timeIntervalSince(last) < task.sampleIntervalSeconds { continue }
            lastSampleAt[task.id] = Date()
            await evaluateOne(task)
        }
    }

    private func evaluateOne(_ task: ScreenWatchTask) async {
        let jpeg: Data
        do {
            jpeg = try await ScreenCaptureService.captureMainDisplayJPEG(maxEdge: 1024, jpegQuality: 0.65)
        } catch {
            events.append(ScreenWatchEvent(taskId: task.id, taskTitle: task.title, kind: .error, detail: error.localizedDescription))
            return
        }

        let localHit: Bool
        if task.conditions.isEmpty {
            localHit = false
        } else {
            var okAll = true
            for cond in task.conditions {
                switch cond {
                case let .ocrContains(text, ci):
                    let ok = await ScreenWatchOCRDetector.imageContains(jpegData: jpeg, substring: text, caseInsensitive: ci)
                    if !ok { okAll = false }
                case let .progressBarFilled(rect, threshold):
                    let ok = ScreenWatchProgressHeuristic.progressLikelyFilled(jpegData: jpeg, rect: rect, deltaThreshold: threshold)
                    if !ok { okAll = false }
                }
            }
            localHit = okAll
        }

        if localHit {
            fireHit(task: task, detail: "本地规则已满足（OCR/亮度）。")
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
                fireHit(task: task, detail: "模型兜底判定：YES（\(ans.prefix(80))）")
            }
        } catch {
            events.append(ScreenWatchEvent(taskId: task.id, taskTitle: task.title, kind: .error, detail: "模型兜底失败：\(error.localizedDescription)"))
        }
    }

    private func fireHit(task: ScreenWatchTask, detail: String) {
        var t = task
        t.isEnabled = false
        tasks.upsert(t)
        events.append(ScreenWatchEvent(taskId: task.id, taskTitle: task.title, kind: .hit, detail: detail))
        onHit?(task.title, detail)
    }
}
