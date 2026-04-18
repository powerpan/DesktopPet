//
// KeychainStore.swift
// DeepSeek API Key 存取（不落 UserDefaults）。
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "io.github.powerpan.DesktopPet.deepseek.apiKey"
    private static let account = "default"

    static func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    static func readAPIKey() -> String? {
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

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        NotificationCenter.default.post(name: .desktopPetAPIKeyDidChange, object: nil)
    }
}
