//
// SettingsViewModel.swift
// 设置状态与 UserDefaults 持久化：穿透、巡逻（含区域）、缩放；缩放读出后夹紧到与 Slider 一致的范围。
//

import Combine
import Foundation
import SwiftUI

private enum SettingsKeys {
    static let clickThrough = "DesktopPet.settings.clickThrough"
    static let patrol = "DesktopPet.settings.patrol"
    /// `PatrolRegionMode.rawValue`
    static let patrolRegion = "DesktopPet.settings.patrolRegion"
    static let patrolIntervalSeconds = "DesktopPet.settings.patrolIntervalSeconds"
    static let patrolEdgeMargin = "DesktopPet.settings.patrolEdgeMargin"
    static let patrolFrontWindowBiasPercent = "DesktopPet.settings.patrolFrontWindowBiasPercent"
    /// **2**：0…100 为「每 tick 进红区概率 %」；**1**：曾存 -100…100 有符号，启动时升为 2 并换算；**0**：更旧版 0…100 直接读入为当前刻度。
    static let patrolFrontWindowBiasLayoutVersion = "DesktopPet.settings.patrolFrontWindowBiasLayoutVersion"
    static let scale = "DesktopPet.settings.petScale"
    /// 条件触发旁白气泡正文字号相对 callout 的倍数（与 `petScale` 独立），默认 1.0。
    static let triggerBubbleFontScale = "DesktopPet.settings.triggerBubbleFontScale"
    static let deskKeyMirror = "DesktopPet.settings.deskKeyMirror"
    /// 为真时：智能体工作台等处显示更偏开发与试跑的说明；为假时面向日常用户、七七口吻。
    static let testingModeUI = "DesktopPet.settings.testingModeUI"
    /// 与「启用测试」配合：打开且「贴近前台窗」为 0、巡逻开启时，在桌面绘制巡逻落点调试遮罩。
    static let patrolLandingDebugOverlay = "DesktopPet.settings.patrolLandingDebugOverlay"
    /// 宠物卡片、对话/饲养浮层、条件旁白气泡等是否使用 SwiftUI 磨砂材质（液态玻璃风格叠层）。
    static let liquidGlassChrome = "DesktopPet.settings.liquidGlassChrome"
    /// `DesktopPetColorSchemePreference.rawValue`
    static let colorSchemePreference = "DesktopPet.settings.colorSchemePreference"
    /// `DesktopPetLiquidGlassVariant.rawValue`（macOS 26+ `Glass` 变体；低系统忽略）。
    static let liquidGlassVariant = "DesktopPet.settings.liquidGlassVariant"
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isClickThroughEnabled: Bool
    @Published var isPatrolEnabled: Bool
    /// 启用巡逻时：随机落点限制在主屏、仅副屏、主+副随机一屏，或「焦点屏」（跟前台应用所在显示器）。
    @Published var patrolRegionMode: PatrolRegionMode
    /// 巡逻定时器间隔（秒），见 `PetConfig.patrolIntervalSecondsMin`…`Max`。
    @Published var patrolIntervalSeconds: Double
    /// 巡逻落点相对 `visibleFrame` 的最小边距（pt）。
    @Published var patrolEdgeMargin: Double
    /// 巡逻「贴近前台窗」刻度 **0…100**：每 tick 以 **k/100** 概率在「前台区域」矩形（与调试红框同源）内均匀取原点；否则强制不进入该区域；取不到红区几何时退回整页均匀随机。
    @Published var patrolFrontWindowBiasPercent: Int
    @Published var petScale: Double
    /// 条件触发云朵气泡内正文字号倍数（与 `petScale` 独立）；**1.0** 为系统 callout 基准，与此前未单独调字体时一致。
    @Published var triggerBubbleFontScale: Double
    /// 桌前文字镜像：是否把全局按键映射到宠物卡片示意键盘（仅内存展示；敏感场景请在设置中关闭）。
    @Published var isDeskKeyMirrorEnabled: Bool
    /// 菜单栏「系统设置 → DesktopPet」中的「启用测试」：打开后工作台文案更长、更偏技术说明，并显示试跑类入口。
    @Published var testingModeEnabled: Bool
    /// 仅调试用：与 `testingModeEnabled` 同时开启且「贴近前台窗」为 0、巡逻开启时，显示巡逻落点范围遮罩。
    @Published var patrolLandingDebugOverlayEnabled: Bool
    /// 是否对宠窗与相关浮层使用磨砂材质；关闭时用不透明语义底色，仍随系统浅色 / 深色变化。
    @Published var isLiquidGlassChromeEnabled: Bool
    /// 宠窗、菜单栏、系统设置、工作台等 SwiftUI 外观：浅色 / 深色 / 跟随系统。
    @Published var colorSchemePreference: DesktopPetColorSchemePreference
    /// macOS 26+ Liquid Glass 变体（`regular` / `clear` / `tint`）；低系统无效果。
    @Published var liquidGlassVariant: DesktopPetLiquidGlassVariant

    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init() {
        if defaults.object(forKey: SettingsKeys.clickThrough) == nil {
            isClickThroughEnabled = true
        } else {
            isClickThroughEnabled = defaults.bool(forKey: SettingsKeys.clickThrough)
        }

        if defaults.object(forKey: SettingsKeys.patrol) == nil {
            isPatrolEnabled = true
        } else {
            isPatrolEnabled = defaults.bool(forKey: SettingsKeys.patrol)
        }

        if let raw = defaults.string(forKey: SettingsKeys.patrolRegion), let m = PatrolRegionMode(rawValue: raw) {
            patrolRegionMode = m
        } else {
            patrolRegionMode = .mainAndSecondary
        }

        if defaults.object(forKey: SettingsKeys.patrolIntervalSeconds) == nil {
            patrolIntervalSeconds = PetConfig.default.patrolInterval
        } else {
            let v = defaults.double(forKey: SettingsKeys.patrolIntervalSeconds)
            patrolIntervalSeconds = min(max(v, PetConfig.patrolIntervalSecondsMin), PetConfig.patrolIntervalSecondsMax)
        }

        if defaults.object(forKey: SettingsKeys.patrolEdgeMargin) == nil {
            patrolEdgeMargin = 48
        } else {
            let v = defaults.double(forKey: SettingsKeys.patrolEdgeMargin)
            patrolEdgeMargin = min(max(v, PetConfig.patrolEdgeMarginMin), PetConfig.patrolEdgeMarginMax)
        }

        let layoutVer = defaults.integer(forKey: SettingsKeys.patrolFrontWindowBiasLayoutVersion)
        if layoutVer >= 2 {
            let v = defaults.integer(forKey: SettingsKeys.patrolFrontWindowBiasPercent)
            patrolFrontWindowBiasPercent = min(100, max(0, v))
        } else if layoutVer == 1 {
            let signed = defaults.integer(forKey: SettingsKeys.patrolFrontWindowBiasPercent)
            let s = min(100, max(-100, signed))
            let migratedK = Int(((Double(s) + 100) / 2).rounded())
            let k = min(100, max(0, migratedK))
            patrolFrontWindowBiasPercent = k
            defaults.set(k, forKey: SettingsKeys.patrolFrontWindowBiasPercent)
            defaults.set(2, forKey: SettingsKeys.patrolFrontWindowBiasLayoutVersion)
        } else if defaults.object(forKey: SettingsKeys.patrolFrontWindowBiasPercent) == nil {
            patrolFrontWindowBiasPercent = 38
            defaults.set(38, forKey: SettingsKeys.patrolFrontWindowBiasPercent)
            defaults.set(2, forKey: SettingsKeys.patrolFrontWindowBiasLayoutVersion)
        } else {
            let legacy = defaults.integer(forKey: SettingsKeys.patrolFrontWindowBiasPercent)
            let k = min(100, max(0, legacy))
            patrolFrontWindowBiasPercent = k
            defaults.set(k, forKey: SettingsKeys.patrolFrontWindowBiasPercent)
            defaults.set(2, forKey: SettingsKeys.patrolFrontWindowBiasLayoutVersion)
        }

        let rawPetScale: Double
        if defaults.object(forKey: SettingsKeys.scale) == nil {
            rawPetScale = 1.0
        } else {
            rawPetScale = defaults.double(forKey: SettingsKeys.scale)
        }
        petScale = min(max(rawPetScale, PetConfig.petScaleMin), PetConfig.petScaleMax)

        let rawBubbleFont: Double
        if defaults.object(forKey: SettingsKeys.triggerBubbleFontScale) == nil {
            rawBubbleFont = PetConfig.triggerBubbleFontScaleMin
        } else {
            rawBubbleFont = defaults.double(forKey: SettingsKeys.triggerBubbleFontScale)
        }
        triggerBubbleFontScale = PetConfig.clampedTriggerBubbleFontScale(rawBubbleFont)

        if defaults.object(forKey: SettingsKeys.deskKeyMirror) == nil {
            isDeskKeyMirrorEnabled = true
        } else {
            isDeskKeyMirrorEnabled = defaults.bool(forKey: SettingsKeys.deskKeyMirror)
        }

        testingModeEnabled = defaults.object(forKey: SettingsKeys.testingModeUI) as? Bool ?? false

        patrolLandingDebugOverlayEnabled = defaults.bool(forKey: SettingsKeys.patrolLandingDebugOverlay)

        if defaults.object(forKey: SettingsKeys.liquidGlassChrome) == nil {
            isLiquidGlassChromeEnabled = true
        } else {
            isLiquidGlassChromeEnabled = defaults.bool(forKey: SettingsKeys.liquidGlassChrome)
        }

        if let raw = defaults.string(forKey: SettingsKeys.colorSchemePreference),
           let p = DesktopPetColorSchemePreference(rawValue: raw) {
            colorSchemePreference = p
        } else {
            colorSchemePreference = .system
        }

        if let raw = defaults.string(forKey: SettingsKeys.liquidGlassVariant),
           let v = DesktopPetLiquidGlassVariant(rawValue: raw) {
            liquidGlassVariant = v
        } else {
            liquidGlassVariant = .regular
        }

        // 跳过首帧，避免 init 时把默认值再写回磁盘
        $isClickThroughEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.clickThrough)
            }
            .store(in: &cancellables)

        $isPatrolEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.patrol)
            }
            .store(in: &cancellables)

        $patrolRegionMode
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: SettingsKeys.patrolRegion)
            }
            .store(in: &cancellables)

        $patrolIntervalSeconds
            .dropFirst()
            .sink { [weak self] raw in
                guard let self else { return }
                let v = min(max(raw, PetConfig.patrolIntervalSecondsMin), PetConfig.patrolIntervalSecondsMax)
                if v != raw { self.patrolIntervalSeconds = v }
                self.defaults.set(v, forKey: SettingsKeys.patrolIntervalSeconds)
            }
            .store(in: &cancellables)

        $patrolEdgeMargin
            .dropFirst()
            .sink { [weak self] raw in
                guard let self else { return }
                let v = min(max(raw, PetConfig.patrolEdgeMarginMin), PetConfig.patrolEdgeMarginMax)
                if v != raw { self.patrolEdgeMargin = v }
                self.defaults.set(v, forKey: SettingsKeys.patrolEdgeMargin)
            }
            .store(in: &cancellables)

        $patrolFrontWindowBiasPercent
            .dropFirst()
            .sink { [weak self] raw in
                guard let self else { return }
                let v = min(100, max(0, raw))
                if v != raw { self.patrolFrontWindowBiasPercent = v }
                self.defaults.set(v, forKey: SettingsKeys.patrolFrontWindowBiasPercent)
                self.defaults.set(2, forKey: SettingsKeys.patrolFrontWindowBiasLayoutVersion)
            }
            .store(in: &cancellables)

        $petScale
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.scale)
            }
            .store(in: &cancellables)

        $triggerBubbleFontScale
            .dropFirst()
            .sink { [weak self] value in
                let v = PetConfig.clampedTriggerBubbleFontScale(value)
                self?.defaults.set(v, forKey: SettingsKeys.triggerBubbleFontScale)
            }
            .store(in: &cancellables)

        $isDeskKeyMirrorEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.deskKeyMirror)
            }
            .store(in: &cancellables)

        $testingModeEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.testingModeUI)
            }
            .store(in: &cancellables)

        $patrolLandingDebugOverlayEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.patrolLandingDebugOverlay)
            }
            .store(in: &cancellables)

        $isLiquidGlassChromeEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.liquidGlassChrome)
            }
            .store(in: &cancellables)

        $colorSchemePreference
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: SettingsKeys.colorSchemePreference)
            }
            .store(in: &cancellables)

        $liquidGlassVariant
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: SettingsKeys.liquidGlassVariant)
            }
            .store(in: &cancellables)
    }
}
