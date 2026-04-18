//
// AgentSettingsStore.swift
// 智能体非敏感配置（UserDefaults）；API Key 见 KeychainStore。
//

import Combine
import Foundation
import SwiftUI

private enum AgentSettingsKeys {
    static let baseURL = "DesktopPet.agent.baseURL"
    static let model = "DesktopPet.agent.model"
    static let systemPrompt = "DesktopPet.agent.systemPrompt"
    static let temperature = "DesktopPet.agent.temperature"
    static let maxTokens = "DesktopPet.agent.maxTokens"
    static let attachKeySummary = "DesktopPet.agent.attachKeySummary"
    static let keyboardTriggerEnabled = "DesktopPet.agent.keyboardTriggerEnabled"
    static let screenSnapTriggerEnabled = "DesktopPet.agent.screenSnapTriggerEnabled"
    static let triggers = "DesktopPet.agent.triggers"
}

@MainActor
final class AgentSettingsStore: ObservableObject {
    @Published var baseURL: String
    @Published var model: String
    @Published var systemPrompt: String
    @Published var temperature: Double
    @Published var maxTokens: Int
    /// 是否在请求中附带键入摘要（默认关，隐私风险）
    @Published var attachKeySummary: Bool
    /// 键盘模式触发总开关（仍受每条 trigger 控制）
    @Published var keyboardTriggerMasterEnabled: Bool
    @Published var screenSnapTriggerMasterEnabled: Bool
    @Published var triggers: [AgentTriggerRule]

    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init() {
        baseURL = defaults.string(forKey: AgentSettingsKeys.baseURL) ?? "https://api.deepseek.com"
        model = defaults.string(forKey: AgentSettingsKeys.model) ?? "deepseek-chat"
        systemPrompt = defaults.string(forKey: AgentSettingsKeys.systemPrompt)
            ?? "你是「七七猫」，一只住在用户桌面上的小猫助手。回答简短、可爱，用简体中文。"
        temperature = defaults.object(forKey: AgentSettingsKeys.temperature) as? Double ?? 0.7
        maxTokens = defaults.object(forKey: AgentSettingsKeys.maxTokens) as? Int ?? 512
        attachKeySummary = defaults.bool(forKey: AgentSettingsKeys.attachKeySummary)
        keyboardTriggerMasterEnabled = defaults.bool(forKey: AgentSettingsKeys.keyboardTriggerEnabled)
        screenSnapTriggerMasterEnabled = defaults.bool(forKey: AgentSettingsKeys.screenSnapTriggerEnabled)
        if let data = defaults.data(forKey: AgentSettingsKeys.triggers),
           let decoded = try? JSONDecoder().decode([AgentTriggerRule].self, from: data) {
            triggers = decoded
        } else {
            triggers = [
                .new(kind: .timer),
                .new(kind: .randomIdle),
            ]
        }

        $baseURL.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.baseURL) }.store(in: &cancellables)
        $model.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.model) }.store(in: &cancellables)
        $systemPrompt.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.systemPrompt) }.store(in: &cancellables)
        $temperature.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.temperature) }.store(in: &cancellables)
        $maxTokens.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.maxTokens) }.store(in: &cancellables)
        $attachKeySummary.dropFirst().sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.attachKeySummary) }.store(in: &cancellables)
        $keyboardTriggerMasterEnabled.dropFirst().sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.keyboardTriggerEnabled) }.store(in: &cancellables)
        $screenSnapTriggerMasterEnabled.dropFirst().sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.screenSnapTriggerEnabled) }.store(in: &cancellables)

        $triggers
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] rules in
                guard let self else { return }
                if let data = try? JSONEncoder().encode(rules) {
                    self.defaults.set(data, forKey: AgentSettingsKeys.triggers)
                }
            }
            .store(in: &cancellables)
    }

    func upsertTrigger(_ rule: AgentTriggerRule) {
        if let i = triggers.firstIndex(where: { $0.id == rule.id }) {
            triggers[i] = rule
        } else {
            triggers.append(rule)
        }
    }

    func removeTrigger(id: UUID) {
        triggers.removeAll { $0.id == id }
    }

    func updateTrigger(id: UUID, mutate: (inout AgentTriggerRule) -> Void) {
        guard let i = triggers.firstIndex(where: { $0.id == id }) else { return }
        var r = triggers[i]
        mutate(&r)
        triggers[i] = r
    }
}
