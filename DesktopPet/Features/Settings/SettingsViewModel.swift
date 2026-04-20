//
// SettingsViewModel.swift
// 设置状态与 UserDefaults 持久化：穿透、巡逻、缩放；缩放读出后夹紧到与 Slider 一致的范围。
//

import Combine
import Foundation
import SwiftUI

private enum SettingsKeys {
    static let clickThrough = "DesktopPet.settings.clickThrough"
    static let patrol = "DesktopPet.settings.patrol"
    static let scale = "DesktopPet.settings.petScale"
    static let deskKeyMirror = "DesktopPet.settings.deskKeyMirror"
    /// 为真时：智能体工作台等处显示更偏开发与试跑的说明；为假时面向日常用户、七七口吻。
    static let testingModeUI = "DesktopPet.settings.testingModeUI"
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isClickThroughEnabled: Bool
    @Published var isPatrolEnabled: Bool
    @Published var petScale: Double
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

        let rawPetScale: Double
        if defaults.object(forKey: SettingsKeys.scale) == nil {
            rawPetScale = 1.0
        } else {
            rawPetScale = defaults.double(forKey: SettingsKeys.scale)
        }
        petScale = min(max(rawPetScale, PetConfig.petScaleMin), PetConfig.petScaleMax)

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

        $petScale
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: SettingsKeys.scale)
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
