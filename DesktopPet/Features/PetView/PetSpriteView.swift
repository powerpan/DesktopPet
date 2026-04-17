import SwiftUI

struct PetSpriteView: View {
    @EnvironmentObject private var stateMachine: PetStateMachine

    var body: some View {
        VStack(spacing: 10) {
            Text(PetAnimationDriver.title(for: stateMachine.state))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .accessibilityLabel(PetAnimationDriver.accessibilityLabel(for: stateMachine.state))

            Text(stateMachine.state.rawValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
