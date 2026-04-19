//
// KeychainStore.swift
// 各服务商 API Key 分账户存于钥匙串（不落 UserDefaults）；兼容旧版单一 DeepSeek 条目。
//

import Foundation
import Security

enum KeychainStore {
    /// 新版：按 `AgentAPIProvider.rawValue` 作为 account。
    private static let unifiedService = "io.github.powerpan.DesktopPet.agent.apiKey"
    /// 旧版 DeepSeek 单 Key。
    private static let legacyService = "io.github.powerpan.DesktopPet.deepseek.apiKey"
    private static let legacyAccount = "default"

    static func keychainAccount(for provider: AgentAPIProvider) -> String {
        provider.rawValue
    }

    // MARK: - 读写

    static func saveAPIKey(_ value: String, forProvider provider: AgentAPIProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = keychainAccount(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unifiedService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "DesktopPet.Keychain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "API Key 不能为空（请粘贴有效内容，或使用「清除」按钮）。"]
            )
        }
        let data = Data(trimmed.utf8)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain 写入失败 (\(status))"])
        }
        NotificationCenter.default.post(name: .desktopPetAPIKeyDidChange, object: nil)
    }

    static func readAPIKey(forProvider provider: AgentAPIProvider) -> String? {
        let account = keychainAccount(for: provider)
        if let s = readPassword(service: unifiedService, account: account), !s.isEmpty {
            return s
        }
        if provider == .deepseek, let legacy = readPassword(service: legacyService, account: legacyAccount), !legacy.isEmpty {
            return legacy
        }
        return nil
    }

    static func deleteAPIKey(forProvider provider: AgentAPIProvider) {
        let account = keychainAccount(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unifiedService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if provider == .deepseek {
            let legacy: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: legacyAccount,
            ]
            SecItemDelete(legacy as CFDictionary)
        }
        NotificationCenter.default.post(name: .desktopPetAPIKeyDidChange, object: nil)
    }

    // MARK: - 兼容旧调用（仅 DeepSeek / 旧 default）

    static func readAPIKey() -> String? {
        readAPIKey(forProvider: .deepseek)
    }

    static func saveAPIKey(_ value: String) throws {
        try saveAPIKey(value, forProvider: .deepseek)
    }

    static func deleteAPIKey() {
        deleteAPIKey(forProvider: .deepseek)
    }

    // MARK: - Private

    private static func readPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data, let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
