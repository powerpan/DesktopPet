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
            Toggle("液态玻璃效果（磨砂叠层）", isOn: $viewModel.isLiquidGlassChromeEnabled)
            Text("开启时：在 macOS 26 及以上使用系统 SwiftUI「Liquid Glass」（glassEffect）；较低系统仍为磨砂材质。关闭后上述界面改为不透明白底，仍随系统浅色 / 深色外观适配。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.isLiquidGlassChromeEnabled {
                Picker("液态玻璃风格", selection: $viewModel.liquidGlassVariant) {
                    ForEach(DesktopPetLiquidGlassVariant.allCases) { v in
                        Text(v.pickerLabel).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                Text("对应 Apple `Glass`：`标准`、更通透的 `更透`（文档建议在 `clear` 下加轻微压暗底）、`淡着色`（`tint`）。无单独模糊强度 API。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("界面外观", selection: $viewModel.colorSchemePreference) {
                ForEach(DesktopPetColorSchemePreference.allCases) { mode in
                    Text(mode.pickerLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("影响宠物窗口、菜单栏爪印菜单、本页系统设置、智能体工作台与权限说明窗；与 macOS 系统「外观」独立，可选跟随系统。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("桌前按键镜像（文字）", isOn: $viewModel.isDeskKeyMirrorEnabled)
            Toggle("启用巡逻", isOn: $viewModel.isPatrolEnabled)
            if viewModel.isPatrolEnabled {
                Picker("巡逻区域", selection: $viewModel.patrolRegionMode) {
                    ForEach(PatrolRegionMode.allCases) { mode in
                        Text(mode.pickerLabel).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Text("「仅主屏」指系统设置里作主显示器的那一块（显示器排列里带白条图标的那屏）。仅副屏：多块外接时每次随机选其中一块非主显示器；无外接则退回主显示器。主屏 + 副屏：每次巡逻在已连接屏幕中随机选一屏。焦点屏：每次巡逻 tick 根据当前前台应用（不含桌宠）窗口所在显示器决定巡逻范围；取不到前台窗时用鼠标所在屏，再退回主屏。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("巡逻间隔")
                    Slider(
                        value: $viewModel.patrolIntervalSeconds,
                        in: PetConfig.patrolIntervalSecondsMin...PetConfig.patrolIntervalSecondsMax,
                        step: 1
                    )
                    Text("\(Int(viewModel.patrolIntervalSeconds.rounded())) 秒")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                HStack {
                    Text("巡逻靠边距")
                    Slider(
                        value: $viewModel.patrolEdgeMargin,
                        in: PetConfig.patrolEdgeMarginMin...PetConfig.patrolEdgeMarginMax,
                        step: 2
                    )
                    Text(String(format: "%.0f pt", viewModel.patrolEdgeMargin))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                HStack {
                    Text("贴近前台窗")
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.patrolFrontWindowBiasPercent) },
                            set: { viewModel.patrolFrontWindowBiasPercent = Int($0.rounded()) }
                        ),
                        in: 0 ... 100,
                        step: 1
                    )
                    Text("\(viewModel.patrolFrontWindowBiasPercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                MarkdownInlineText(source: AgentSettingsUICopy.settingsPanelPatrolTuneFooter(testing: viewModel.testingModeEnabled))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("宠物缩放")
                Slider(value: $viewModel.petScale, in: PetConfig.petScaleMin...PetConfig.petScaleMax, step: 0.1)
                Text(String(format: "%.1fx", viewModel.petScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("旁白气泡字体")
                Slider(
                    value: $viewModel.triggerBubbleFontScale,
                    in: PetConfig.triggerBubbleFontScaleMin...PetConfig.triggerBubbleFontScaleMax,
                    step: 0.05
                )
                Text(String(format: "%.2fx", viewModel.triggerBubbleFontScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            MarkdownInlineText(source: AgentSettingsUICopy.settingsPanelBubbleFontCaption(testing: viewModel.testingModeEnabled))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("启用测试", isOn: $viewModel.testingModeEnabled)
            if viewModel.testingModeEnabled {
                Toggle("巡逻落点预览（调试用）", isOn: $viewModel.patrolLandingDebugOverlayEnabled)
                Text("需同时打开「启用巡逻」并把「贴近前台窗」调到 0。遮罩：蓝=巡逻 visibleFrame；绿=宠物可覆盖区；橙虚线=合法原点域；红=掷骰命中时在其中随机取点的「前台区域」（与巡逻红内分支同源）。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .preferredColorScheme(viewModel.colorSchemePreference.resolvedPreferredColorScheme)
    }
}

#Preview {
    SettingsPanelView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AppCoordinator())
}
