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
    static let scale = "DesktopPet.settings.petScale"
    /// 条件触发旁白气泡正文字号相对 callout 的倍数（与 `petScale` 独立），默认 1.0。
    static let triggerBubbleFontScale = "DesktopPet.settings.triggerBubbleFontScale"
    static let deskKeyMirror = "DesktopPet.settings.deskKeyMirror"
    /// 为真时：智能体工作台等处显示更偏开发与试跑的说明；为假时面向日常用户、七七口吻。
    static let testingModeUI = "DesktopPet.settings.testingModeUI"
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isClickThroughEnabled: Bool
    @Published var isPatrolEnabled: Bool
    /// 启用巡逻时：随机落点限制在主屏、仅副屏、主+副随机一屏，或「焦点屏」（跟前台应用所在显示器）。
    @Published var patrolRegionMode: PatrolRegionMode
    @Published var petScale: Double
    /// 条件触发云朵气泡内正文字号倍数（与 `petScale` 独立）；**1.0** 为系统 callout 基准，与此前未单独调字体时一致。
    @Published var triggerBubbleFontScale: Double
    /// 桌前文字镜像：是否把全局按键映射到宠物卡片示意键盘（仅内存展示；敏感场景请在设置中关闭）。
    @Published var isDeskKeyMirrorEnabled: Bool
    /// 菜单栏「系统设置 → DesktopPet」中的「启用测试」：打开后工作台文案更长、更偏技术说明，并显示试跑类入口。
    @Published var testingModeEnabled: Bool

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
    }
}
