//
// SettingsPanelView.swift
// 系统「设置」场景中的表单：绑定 SettingsViewModel 的穿透、巡逻与缩放。
//

import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle("启用鼠标穿透", isOn: $viewModel.isClickThroughEnabled)
            Toggle("启用巡逻", isOn: $viewModel.isPatrolEnabled)
            HStack {
                Text("宠物缩放")
                Slider(value: $viewModel.petScale, in: PetConfig.petScaleMin...PetConfig.petScaleMax, step: 0.1)
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
        .environmentObject(SettingsViewModel())
}
