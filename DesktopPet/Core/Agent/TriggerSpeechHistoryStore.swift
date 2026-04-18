//
// TriggerSpeechHistoryStore.swift
// 条件触发旁白历史（UserDefaults + Codable，条数上限）。
//

import Foundation
import SwiftUI

private enum TriggerSpeechHistoryKeys {
    static let records = "DesktopPet.agent.triggerSpeechHistory.v1"
}

@MainActor
final class TriggerSpeechHistoryStore: ObservableObject {
    @Published private(set) var records: [TriggerSpeechRecord] = []

    private let defaults = UserDefaults.standard
    private let maxRecords = 200

    init() {
        load()
    }

    func append(text: String, kind: AgentTriggerKind) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let r = TriggerSpeechRecord(id: UUID(), text: t, triggerKind: kind, createdAt: Date())
        records.insert(r, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        persist()
    }

    func clearAll() {
        records = []
        persist()
    }

    private func load() {
        if let data = defaults.data(forKey: TriggerSpeechHistoryKeys.records),
           let decoded = try? JSONDecoder().decode([TriggerSpeechRecord].self, from: data) {
            records = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: TriggerSpeechHistoryKeys.records)
        }
    }
}
