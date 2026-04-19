//
// SettingsPanelView.swift
// 系统「设置」场景中的表单：绑定 SettingsViewModel 的穿透、巡逻与缩放（桌宠外观与行为）。
//

import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section {
                Text("此处为 macOS 系统设置中的「DesktopPet」面板，只调整桌宠窗口本身：穿透、巡逻、缩放与桌镜。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("模型、API Key、Slack、会话、触发器、盯屏等请在菜单栏 **「打开智能体工作台…」**（独立窗口）；Slack 在「连接」分区配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("启用鼠标穿透", isOn: $viewModel.isClickThroughEnabled)
            Toggle("桌前按键镜像（文字）", isOn: $viewModel.isDeskKeyMirrorEnabled)
            Toggle("启用巡逻", isOn: $viewModel.isPatrolEnabled)
            HStack {
                Text("宠物缩放")
                Slider(value: $viewModel.petScale, in: PetConfig.petScaleMin...PetConfig.petScaleMax, step: 0.1)
                Text(String(format: "%.1fx", viewModel.petScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("打开智能体工作台…") {
                    coordinator.presentAgentSettingsWindow()
                }
            } header: {
                Text("智能体与自动化")
            } footer: {
                Text("与上方面板分离：工作台含连接（含 Slack）、对话、陪伴、自动化与集成（盯屏）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 340)
    }
}

#Preview {
    SettingsPanelView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AppCoordinator())
}
