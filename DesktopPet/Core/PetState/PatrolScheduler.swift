//
// PatrolScheduler.swift
// 巡逻定时器：按固定间隔回调，由 AppCoordinator 内决定是否真的移动窗口（受设置与可见性约束）。
//

import Foundation

@MainActor
final class PatrolScheduler {
    private var timer: Timer?
    var onPatrolTick: (() -> Void)?

    func start(interval: TimeInterval = PetConfig.default.patrolInterval) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.onPatrolTick?()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Logger.shared.info("Patrol scheduler started.")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
