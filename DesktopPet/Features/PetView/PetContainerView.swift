import SwiftUI

struct PetContainerView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var stateMachine: PetStateMachine

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PetSpriteView()
            SettingsFloatingButton(
                isClickThrough: Binding(
                    get: { settings.isClickThroughEnabled },
                    set: { settings.isClickThroughEnabled = $0 }
                )
            )
        }
        .padding(8)
        .frame(width: 220, height: 220)
        .scaleEffect(settings.petScale)
        .animation(.easeInOut(duration: 0.2), value: settings.petScale)
    }
}

#Preview {
    PetContainerView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PetStateMachine())
}
