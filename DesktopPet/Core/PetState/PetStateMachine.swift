import Foundation
import SwiftUI

@MainActor
final class PetStateMachine: ObservableObject {
    @Published private(set) var state: PetState = .idle

    private var transientTask: Task<Void, Never>?

    func handle(_ event: InteractionEvent) {
        switch event {
        case .keyboardInput:
            if state == .sleep {
                transition(to: .idle)
            }
            scheduleTransient(to: .keyTap, durationNanoseconds: 160_000_000)
        case .mouseMovedFast:
            if state == .sleep {
                transition(to: .idle)
            }
            scheduleTransient(to: .jump, durationNanoseconds: 320_000_000)
        case let .mouseHoverNear(distance):
            if state == .sleep {
                transition(to: .idle)
            }
            if distance < 90 {
                transition(to: .idle)
            }
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

    private func scheduleTransient(to newState: PetState, durationNanoseconds: UInt64) {
        transientTask?.cancel()
        transition(to: newState)
        transientTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else { return }
            transition(to: .idle)
        }
    }
}
