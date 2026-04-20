//
// AgentSettingsStore.swift
// 智能体非敏感配置（UserDefaults）；多套 Base URL / 模型分列保存，当前服务商见 `activeAPIProvider`；API Key 见 KeychainStore。
//

import Combine
import Foundation
import SwiftUI

private enum AgentSettingsKeys {
    /// 仅一次：为旧配置插入「饲养互动」默认规则（用户可删除且不会再次自动插入）。
    static let careTriggerMigrationDone = "DesktopPet.agent.careTriggerMigrationDone"
    /// 仅一次：插入「数值与成长旁白」默认规则。
    static let petStatAutomationMigrationDone = "DesktopPet.agent.petStatAutomationMigrationDone"
    static let baseURL = "DesktopPet.agent.baseURL"
    static let model = "DesktopPet.agent.model"
    static let systemPrompt = "DesktopPet.agent.systemPrompt"
    static let temperature = "DesktopPet.agent.temperature"
    static let maxTokens = "DesktopPet.agent.maxTokens"
    static let attachKeySummary = "DesktopPet.agent.attachKeySummary"
    static let keyboardTriggerEnabled = "DesktopPet.agent.keyboardTriggerEnabled"
    static let screenSnapTriggerEnabled = "DesktopPet.agent.screenSnapTriggerEnabled"
    static let triggerDefaultTemperature = "DesktopPet.agent.triggerDefaultTemperature"
    static let triggerDefaultMaxTokens = "DesktopPet.agent.triggerDefaultMaxTokens"
    static let triggers = "DesktopPet.agent.triggers"
    /// 2 = 含旁白路由 `routes` / `defaultPromptTemplate` 的结构；用于首次升级后回写 UserDefaults。
    static let triggersFormatVersion = "DesktopPet.agent.triggersFormatVersion"
    static let triggerSlackNotifyMasterEnabled = "DesktopPet.agent.triggerSlackNotifyMasterEnabled"
}

private enum ProviderStorage {
    static let slotsMigrated = "DesktopPet.agent.providerSlotsV1"
    static let active = "DesktopPet.agent.activeProvider"

    static func urlKey(_ p: AgentAPIProvider) -> String {
        "DesktopPet.agent.provider.\(p.rawValue).baseURL"
    }

    static func modelKey(_ p: AgentAPIProvider) -> String {
        "DesktopPet.agent.provider.\(p.rawValue).model"
    }
}

@MainActor
final class AgentSettingsStore: ObservableObject {
    /// 当前使用的服务商（决定读写的 Base URL / 模型槽位与钥匙串账户）。
    @Published var activeAPIProvider: AgentAPIProvider
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
    /// 条件旁白请求的默认温度（与「连接」里长对话温度独立）。
    @Published var triggerDefaultTemperature: Double
    /// 条件旁白请求的默认 max_tokens（与长对话独立）。
    @Published var triggerDefaultMaxTokens: Int
    /// 为真时，允许各条触发器上的「同步 Slack」生效；否则全部不按 Slack 推送旁白。
    @Published var triggerSlackNotifyMasterEnabled: Bool
    @Published var triggers: [AgentTriggerRule]

    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init() {
        let legacyBase = defaults.string(forKey: AgentSettingsKeys.baseURL) ?? AgentAPIProvider.deepseek.defaultBaseURL
        let legacyModel = defaults.string(forKey: AgentSettingsKeys.model) ?? AgentAPIProvider.deepseek.defaultModel
        Self.migrateProviderSlotsIfNeeded(defaults: defaults, legacyBase: legacyBase, legacyModel: legacyModel)

        let active = AgentAPIProvider(rawValue: defaults.string(forKey: ProviderStorage.active) ?? "") ?? .deepseek
        activeAPIProvider = active
        let slot = Self.loadSlot(defaults: defaults, for: active)
        baseURL = slot.url
        model = slot.model

        systemPrompt = defaults.string(forKey: AgentSettingsKeys.systemPrompt)
            ?? "你是「七七猫」，一只住在用户桌面上的小猫助手。回答简短、可爱，用简体中文。"
        temperature = defaults.object(forKey: AgentSettingsKeys.temperature) as? Double ?? 0.7
        maxTokens = defaults.object(forKey: AgentSettingsKeys.maxTokens) as? Int ?? 512
        attachKeySummary = defaults.bool(forKey: AgentSettingsKeys.attachKeySummary)
        keyboardTriggerMasterEnabled = defaults.bool(forKey: AgentSettingsKeys.keyboardTriggerEnabled)
        screenSnapTriggerMasterEnabled = defaults.bool(forKey: AgentSettingsKeys.screenSnapTriggerEnabled)
        triggerDefaultTemperature = defaults.object(forKey: AgentSettingsKeys.triggerDefaultTemperature) as? Double ?? 0.7
        triggerDefaultMaxTokens = defaults.object(forKey: AgentSettingsKeys.triggerDefaultMaxTokens) as? Int ?? 256
        triggerSlackNotifyMasterEnabled = defaults.bool(forKey: AgentSettingsKeys.triggerSlackNotifyMasterEnabled)
        if let data = defaults.data(forKey: AgentSettingsKeys.triggers),
           let decoded = try? JSONDecoder().decode([AgentTriggerRule].self, from: data) {
            triggers = decoded
        } else {
            triggers = [
                .new(kind: .timer),
                .new(kind: .randomIdle),
            ]
        }
        if !defaults.bool(forKey: AgentSettingsKeys.careTriggerMigrationDone) {
            if !triggers.contains(where: { $0.kind == .careInteraction }) {
                triggers.append(.new(kind: .careInteraction))
            }
            defaults.set(true, forKey: AgentSettingsKeys.careTriggerMigrationDone)
        }
        if !defaults.bool(forKey: AgentSettingsKeys.petStatAutomationMigrationDone) {
            if !triggers.contains(where: { $0.kind == .petStatAutomation }) {
                triggers.append(.new(kind: .petStatAutomation))
            }
            defaults.set(true, forKey: AgentSettingsKeys.petStatAutomationMigrationDone)
        }

        let triggersVer = defaults.integer(forKey: AgentSettingsKeys.triggersFormatVersion)
        if triggersVer < 2, let migrated = try? JSONEncoder().encode(triggers) {
            defaults.set(migrated, forKey: AgentSettingsKeys.triggers)
            defaults.set(2, forKey: AgentSettingsKeys.triggersFormatVersion)
        }

        // Base URL / 模型与「当前服务商」强相关：若用 debounce，用户快速切换服务商时，迟到的写入可能污染新槽位，故改为即时落盘。
        $baseURL.dropFirst().sink { [weak self] v in
            guard let self else { return }
            self.defaults.set(v, forKey: ProviderStorage.urlKey(self.activeAPIProvider))
            self.defaults.set(v, forKey: AgentSettingsKeys.baseURL)
        }.store(in: &cancellables)

        $model.dropFirst().sink { [weak self] v in
            guard let self else { return }
            self.defaults.set(v, forKey: ProviderStorage.modelKey(self.activeAPIProvider))
            self.defaults.set(v, forKey: AgentSettingsKeys.model)
        }.store(in: &cancellables)

        $systemPrompt.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.systemPrompt) }.store(in: &cancellables)
        $temperature.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.temperature) }.store(in: &cancellables)
        $maxTokens.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.maxTokens) }.store(in: &cancellables)
        $attachKeySummary.dropFirst().sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.attachKeySummary) }.store(in: &cancellables)
        $keyboardTriggerMasterEnabled.dropFirst().sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.keyboardTriggerEnabled) }.store(in: &cancellables)
        $screenSnapTriggerMasterEnabled.dropFirst().sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.screenSnapTriggerEnabled) }.store(in: &cancellables)
        $triggerDefaultTemperature.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.triggerDefaultTemperature) }.store(in: &cancellables)
        $triggerDefaultMaxTokens.dropFirst().debounce(for: .milliseconds(200), scheduler: DispatchQueue.main).sink { [weak self] v in self?.defaults.set(v, forKey: AgentSettingsKeys.triggerDefaultMaxTokens) }.store(in: &cancellables)
        $triggerSlackNotifyMasterEnabled.dropFirst().sink { [weak self] v in
            self?.defaults.set(v, forKey: AgentSettingsKeys.triggerSlackNotifyMasterEnabled)
        }.store(in: &cancellables)

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

    /// 切换当前服务商：先保存当前编辑中的 Base URL / 模型到旧槽位，再载入新槽位。
    func setActiveAPIProvider(_ newProvider: AgentAPIProvider) {
        guard newProvider != activeAPIProvider else { return }
        persistWorkingConnectionToSlot(for: activeAPIProvider)
        activeAPIProvider = newProvider
        defaults.set(newProvider.rawValue, forKey: ProviderStorage.active)
        let slot = Self.loadSlot(defaults: defaults, for: newProvider)
        baseURL = slot.url
        model = slot.model
        defaults.set(baseURL, forKey: AgentSettingsKeys.baseURL)
        defaults.set(model, forKey: AgentSettingsKeys.model)
    }

    private func persistWorkingConnectionToSlot(for provider: AgentAPIProvider) {
        defaults.set(baseURL, forKey: ProviderStorage.urlKey(provider))
        defaults.set(model, forKey: ProviderStorage.modelKey(provider))
    }

    private static func migrateProviderSlotsIfNeeded(defaults: UserDefaults, legacyBase: String, legacyModel: String) {
        guard !defaults.bool(forKey: ProviderStorage.slotsMigrated) else { return }
        for p in AgentAPIProvider.allCases {
            if defaults.string(forKey: ProviderStorage.urlKey(p)) == nil {
                switch p {
                case .deepseek:
                    defaults.set(legacyBase, forKey: ProviderStorage.urlKey(p))
                case .qwenCompatible, .custom:
                    defaults.set(p.defaultBaseURL, forKey: ProviderStorage.urlKey(p))
                }
            }
            if defaults.string(forKey: ProviderStorage.modelKey(p)) == nil {
                switch p {
                case .deepseek:
                    defaults.set(legacyModel, forKey: ProviderStorage.modelKey(p))
                case .qwenCompatible, .custom:
                    defaults.set(p.defaultModel, forKey: ProviderStorage.modelKey(p))
                }
            }
        }
        defaults.set(true, forKey: ProviderStorage.slotsMigrated)
    }

    private static func loadSlot(defaults: UserDefaults, for provider: AgentAPIProvider) -> (url: String, model: String) {
        let u = defaults.string(forKey: ProviderStorage.urlKey(provider)) ?? provider.defaultBaseURL
        let m = defaults.string(forKey: ProviderStorage.modelKey(provider)) ?? provider.defaultModel
        return (u, m)
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
