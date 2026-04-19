//
// ScreenWatchPersistence.swift
// 盯屏任务与事件（UserDefaults + Codable）。
//

import Foundation
import SwiftUI

private enum ScreenWatchKeys {
    static let tasks = "DesktopPet.screenWatch.tasks.v1"
    static let events = "DesktopPet.screenWatch.events.v1"
}

@MainActor
final class ScreenWatchTaskStore: ObservableObject {
    @Published private(set) var tasks: [ScreenWatchTask] = []

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func load() {
        if let data = defaults.data(forKey: ScreenWatchKeys.tasks),
           let decoded = try? JSONDecoder().decode([ScreenWatchTask].self, from: data) {
            tasks = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: ScreenWatchKeys.tasks)
        }
    }

    func upsert(_ task: ScreenWatchTask) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i] = task
        } else {
            tasks.append(task)
        }
        persist()
    }

    func remove(id: UUID) {
        tasks.removeAll { $0.id == id }
        persist()
    }

    func replaceAll(_ new: [ScreenWatchTask]) {
        tasks = new
        persist()
    }
}

@MainActor
final class ScreenWatchEventStore: ObservableObject {
    @Published private(set) var events: [ScreenWatchEvent] = []

    private let defaults = UserDefaults.standard
    private let maxEvents = 200

    init() {
        load()
    }

    private func load() {
        if let data = defaults.data(forKey: ScreenWatchKeys.events),
           let decoded = try? JSONDecoder().decode([ScreenWatchEvent].self, from: data) {
            events = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: ScreenWatchKeys.events)
        }
    }

    func append(_ e: ScreenWatchEvent) {
        events.insert(e, at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
        persist()
    }

    func clear() {
        events = []
        persist()
    }
}
