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

    func append(text: String, kind: AgentTriggerKind, userPrompt: String? = nil, snapshotJPEG: Data? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let prompt = userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID()
        var snapshotFile: String?
        if let data = snapshotJPEG, !data.isEmpty {
            snapshotFile = try? TriggerSpeechSnapshotStorage.saveJPEG(data, recordId: id)
        }
        let r = TriggerSpeechRecord(
            id: id,
            text: t,
            triggerKind: kind,
            createdAt: Date(),
            userPromptSent: (prompt?.isEmpty == false) ? prompt : nil,
            userRequestSnapshotFileName: snapshotFile
        )
        records.insert(r, at: 0)
        if records.count > maxRecords {
            let overflow = records.count - maxRecords
            let dropped = records.suffix(overflow)
            for old in dropped {
                TriggerSpeechSnapshotStorage.deleteFile(storedFileName: old.userRequestSnapshotFileName)
            }
            records = Array(records.prefix(maxRecords))
        }
        persist()
    }

    func clearAll() {
        for r in records {
            TriggerSpeechSnapshotStorage.deleteFile(storedFileName: r.userRequestSnapshotFileName)
        }
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
