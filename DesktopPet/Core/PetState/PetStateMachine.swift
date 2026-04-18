//
// PetStateMachine.swift
// 根据 InteractionEvent 切换宠物状态；短时状态（敲、跳）用 Task 延时后回到 idle。
//

import Foundation
import SwiftUI

@MainActor
final class PetStateMachine: ObservableObject {
    @Published private(set) var state: PetState = .idle

    private var transientTask: Task<Void, Never>?
    private var keyBurstCount = 0
    private var keyBurstDecayTask: Task<Void, Never>?

    func handle(_ event: InteractionEvent) {
        switch event {
        case .keyboardInput:
            if state == .sleep {
                transition(to: .idle)
            }
            bumpKeyBurst()
            let duration = keyTapDurationNanoseconds()
            scheduleTransient(to: .keyTap, durationNanoseconds: duration)
        case .mouseMovedFast:
            if state == .sleep {
                transition(to: .idle)
            }
            // 正在显示敲击反馈时不要被甩鼠打断，否则几乎看不到「敲」
            if state == .keyTap {
                break
            }
            scheduleTransient(to: .jump, durationNanoseconds: 320_000_000)
        case .mouseHoverNear:
            if state == .sleep {
                transition(to: .idle)
            }
            // 悬停只驱动 PointerTrackingModel 的注视偏移，不再改状态机，避免打断 keyTap/jump
        case .patrolRequested:
            if state == .sleep {
                transition(to: .idle)
            }
            transition(to: .walk)
        case .idleTimeout:
            transition(to: .sleep)
        }
    }

    func transition(to newState: PetState) {
        guard newState != state else { return }
        Logger.shared.info("Pet state: \(state.rawValue) -> \(newState.rawValue)")
        state = newState
    }

    /// 先切入短时动画态，再在指定纳秒后回到 idle
    private func scheduleTransient(to newState: PetState, durationNanoseconds: UInt64) {
        transientTask?.cancel()
        transition(to: newState)
        transientTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else { return }
            transition(to: .idle)
        }
    }

    private func bumpKeyBurst() {
        keyBurstCount = min(keyBurstCount + 1, 18)
        keyBurstDecayTask?.cancel()
        keyBurstDecayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            keyBurstCount = max(0, keyBurstCount - 5)
        }
    }

    /// 连击越快，敲击态略短，但仍保留可见下限，避免 UI 来不及刷新。
    private func keyTapDurationNanoseconds() -> UInt64 {
        let base: UInt64 = 260_000_000
        let step: UInt64 = 9_000_000
        let sub = min(UInt64(keyBurstCount), 12) * step
        return max(150_000_000, base &- sub)
    }
}
