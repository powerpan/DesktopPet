//
// ScreenWatchHitFeedbackService.swift
// 盯屏命中后的旁白、气泡与 Slack 线程汇报（从 AppCoordinator 抽离）。
//

import Foundation
import SwiftUI

@MainActor
final class ScreenWatchHitFeedbackService {
    private let agentSessionStore: AgentSessionStore
    private let agentSettingsStore: AgentSettingsStore
    private let agentClient: AgentClient
    private let slackSyncController: SlackSyncController
    private let deliverTriggerSpeech: (TriggerSpeechPayload) -> Void

    init(
        agentSessionStore: AgentSessionStore,
        agentSettingsStore: AgentSettingsStore,
        agentClient: AgentClient,
        slackSyncController: SlackSyncController,
        deliverTriggerSpeech: @escaping (TriggerSpeechPayload) -> Void
    ) {
        self.agentSessionStore = agentSessionStore
        self.agentSettingsStore = agentSettingsStore
        self.agentClient = agentClient
        self.slackSyncController = slackSyncController
        self.deliverTriggerSpeech = deliverTriggerSpeech
    }

    func notifyHit(task: ScreenWatchTask, narrativeKind: ScreenWatchHitNarrativeKind) {
        switch narrativeKind {
        case .visionFallback:
            Task { @MainActor [weak self] in
                guard let self else { return }
                let line = await self.narrateVisionFallbackHit(task: task)
                let text = "【盯屏】\(task.title)\n\(line)"
                self.deliverTriggerSpeech(TriggerSpeechPayload(
                    text: text,
                    triggerKind: .screenWatch,
                    userPrompt: nil,
                    requestSnapshotJPEG: nil
                ))
                await self.postSlackIfNeeded(task: task, body: text)
            }
        case .localHeuristic:
            Task { @MainActor [weak self] in
                guard let self else { return }
                let line = await self.narrateLocalHeuristicHit(taskTitle: task.title)
                let text = "【盯屏】\(task.title)\n\(line)"
                self.deliverTriggerSpeech(TriggerSpeechPayload(
                    text: text,
                    triggerKind: .screenWatch,
                    userPrompt: nil,
                    requestSnapshotJPEG: nil
                ))
                await self.postSlackIfNeeded(task: task, body: text)
            }
        }
    }

    private func postSlackIfNeeded(task: ScreenWatchTask, body: String) async {
        guard task.creationSource == .slackAutomated else { return }
        let ch = task.slackReportChannelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ch.isEmpty else { return }
        let thread = task.slackReportThreadTs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadArg: String? = (thread?.isEmpty == false) ? thread : nil
        await slackSyncController.postSlackThreadReply(channelId: ch, threadTs: threadArg, text: body)
    }

    private func narrateVisionFallbackHit(task: ScreenWatchTask) async -> String {
        let key = KeychainStore.readAPIKey(forProvider: agentSettingsStore.activeAPIProvider)
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.screenWatchVisionFallbackUserFallbackNarrative()
        }
        let hint = task.visionUserHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let hintLine = hint.isEmpty ? "（用户未单独写看图说明，仅依据任务标题理解。）" : "用户当初让你看图判断的要点：\(hint.prefix(200))"
        do {
            var sys = agentSettingsStore.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sys.isEmpty { sys += "\n\n" }
            sys += """
            （本轮附加指示）用户配置的「盯屏任务」已在本机通过截图、由多模态模型判定为「条件已满足」。
            请你以桌宠身份写 1～2 句简短、口语化的中文，温柔地告诉用户「可以过来看一眼啦」或类似陪伴感；可轻轻呼应任务主题，不必照抄标题全文。
            禁止：出现「YES」「NO」「OCR」「多模态」「截图模型」「兜底」「API」「置信度」等技术词；不要复述模型原始输出；不要分点列举；不要「作为人工智能」式套话。总字数 60 字以内。
            只输出旁白正文，不要加引号，不要加「旁白：」等前缀。
            """
            let user = "任务标题（供你把握语气，不必照抄）：\(task.title)\n\(hintLine)"
            let reply = try await agentClient.completeChat(
                baseURL: agentSettingsStore.baseURL,
                model: agentSettingsStore.model,
                apiKey: key,
                systemPrompt: sys,
                messages: [["role": "user", "content": user]],
                temperature: min(1.0, agentSettingsStore.temperature + 0.15),
                maxTokens: 120
            )
            let line = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return Self.screenWatchVisionFallbackUserFallbackNarrative() }
            return line
        } catch {
            return Self.screenWatchVisionFallbackUserFallbackNarrative()
        }
    }

    private static func screenWatchVisionFallbackUserFallbackNarrative() -> String {
        "图上那边已经对上你要的状态啦，快来看一眼，我在这儿陪你～"
    }

    private func narrateLocalHeuristicHit(taskTitle: String) async -> String {
        let key = KeychainStore.readAPIKey(forProvider: agentSettingsStore.activeAPIProvider)
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.screenWatchLocalHeuristicFallbackNarrative()
        }
        do {
            var sys = agentSettingsStore.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sys.isEmpty { sys += "\n\n" }
            sys += """
            （本轮附加指示）用户给你配置派遣的「盯屏任务」（帮用户盯着屏幕进度）刚刚在本机判定为条件已满足（依据屏幕上的文字或进度区域变化，未使用截图问答模型）。
            请你以桌宠身份写 1～2 句简短、口语化的中文，让用户感到被陪伴；可以轻轻呼应任务主题，不必机械重复标题全文。
            禁止：出现「OCR」「亮度」「像素」「启发式」「规则」「模型」「API」等技术词；不要分点列举；不要「作为人工智能」式套话。总字数 60 字以内。
            只输出旁白正文，不要加引号，不要加「旁白：」等前缀。
            """
            let user = "任务标题（供你把握语气，不必照抄）：\(taskTitle)"
            let reply = try await agentClient.completeChat(
                baseURL: agentSettingsStore.baseURL,
                model: agentSettingsStore.model,
                apiKey: key,
                systemPrompt: sys,
                messages: [["role": "user", "content": user]],
                temperature: min(1.0, agentSettingsStore.temperature + 0.15),
                maxTokens: 120
            )
            let line = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return Self.screenWatchLocalHeuristicFallbackNarrative() }
            return line
        } catch {
            return Self.screenWatchLocalHeuristicFallbackNarrative()
        }
    }

    private static func screenWatchLocalHeuristicFallbackNarrative() -> String {
        "好啦，你盯的那件事看起来已经满足条件了，我来喊你一声～"
    }
}
