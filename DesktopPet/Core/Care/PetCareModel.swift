//
// PetCareModel.swift
// 轻量饲养：心情/能量、每日重置、喂食与戳戳冷却、陪伴时长累计。
//

import Combine
import Foundation
import SwiftUI

private enum PetCareKeys {
    static let state = "DesktopPet.care.state"
}

@MainActor
final class PetCareModel: ObservableObject {
    @Published private(set) var state: PetCareState

    private let defaults = UserDefaults.standard
    private var companionTick: Timer?

    /// 喂食冷却（秒）
    let feedCooldown: TimeInterval = 4 * 60 * 60
    /// 戳戳冷却
    let petCooldown: TimeInterval = 30

    init() {
        if let data = defaults.data(forKey: PetCareKeys.state),
           let decoded = try? JSONDecoder().decode(PetCareState.self, from: data) {
            state = decoded
        } else {
            state = PetCareState.neutral
        }
        ensureDayResetIfNeeded()
    }

    func startCompanionTicking(isPetVisible: @escaping () -> Bool) {
        companionTick?.invalidate()
        companionTick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.ensureDayResetIfNeeded()
                guard isPetVisible() else { return }
                var s = self.state
                s.todayCompanionSeconds += 1
                self.state = s
                self.persist()
            }
        }
        if let companionTick {
            RunLoop.main.add(companionTick, forMode: .common)
        }
    }

    func stopCompanionTicking() {
        companionTick?.invalidate()
        companionTick = nil
    }

    private func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func ensureDayResetIfNeeded() {
        let today = dayKey()
        if state.lastResetDayKey != today {
            var s = state
            s.lastResetDayKey = today
            s.todayCompanionSeconds = 0
            s.mood = min(1, s.mood + 0.05)
            s.energy = min(1, s.energy + 0.05)
            state = s
            persist()
        }
    }

    func feedIfAllowed() -> Bool {
        if let last = state.lastFeedAt, Date().timeIntervalSince(last) < feedCooldown {
            return false
        }
        var s = state
        s.lastFeedAt = Date()
        s.mood = min(1, s.mood + 0.12)
        s.energy = min(1, s.energy + 0.15)
        state = s
        persist()
        return true
    }

    func petIfAllowed() -> Bool {
        if let last = state.lastPetAt, Date().timeIntervalSince(last) < petCooldown {
            return false
        }
        var s = state
        s.lastPetAt = Date()
        s.mood = min(1, s.mood + 0.06)
        state = s
        persist()
        return true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: PetCareKeys.state)
        }
    }
}
