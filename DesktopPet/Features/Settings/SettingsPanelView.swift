import SwiftUI

struct SettingsPanelView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Toggle("启用鼠标穿透", isOn: $viewModel.isClickThroughEnabled)
            Toggle("启用巡逻", isOn: $viewModel.isPatrolEnabled)
            HStack {
                Text("宠物缩放")
                Slider(value: $viewModel.petScale, in: 0.6...1.8, step: 0.1)
                Text(String(format: "%.1fx", viewModel.petScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

#Preview {
    SettingsPanelView()
}
