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
                MarkdownInlineText(source: AgentSettingsUICopy.settingsPanelHeaderLine1(testing: viewModel.testingModeEnabled))
                    .foregroundStyle(.secondary)
                MarkdownInlineText(source: AgentSettingsUICopy.settingsPanelHeaderLine2(testing: viewModel.testingModeEnabled))
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
            Toggle("启用测试", isOn: $viewModel.testingModeEnabled)
            Section {
                MarkdownInlineText(source: AgentSettingsUICopy.settingsPanelTestingToggleFooter(testing: viewModel.testingModeEnabled))
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("打开智能体工作台…") {
                    coordinator.presentAgentSettingsWindow()
                }
            } header: {
                Text("智能体与自动化")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.settingsPanelAgentWorkshopFooter(testing: viewModel.testingModeEnabled))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 400, idealWidth: 480, maxWidth: 640)
    }
}

#Preview {
    SettingsPanelView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AppCoordinator())
}
