import SwiftUI

struct PetSpriteView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("CAT")
                .font(.headline)
            Text("动画播放器占位")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
