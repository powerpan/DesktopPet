import Foundation

@MainActor
final class PetStateMachine: ObservableObject {
    @Published private(set) var state: PetState = .idle

    func handle(_ event: InteractionEvent) {
        switch event {
        case .keyboardInput:
            transition(to: .keyTap)
            transition(to: .idle)
        case let .mouseMoved(_, speed):
            transition(to: speed > 80 ? .jump : .idle)
        case .patrolRequested:
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
}
