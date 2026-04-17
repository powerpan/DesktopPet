import SwiftUI

struct PetContainerView: View {
    @State private var isClickThrough = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PetSpriteView()
            SettingsFloatingButton(isClickThrough: $isClickThrough)
        }
        .padding(8)
        .frame(width: 220, height: 220)
        .background(Color.clear)
    }
}

#Preview {
    PetContainerView()
}
