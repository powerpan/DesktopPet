import Combine
import Foundation
import SwiftUI

private enum SettingsKeys {
    static let clickThrough = "DesktopPet.settings.clickThrough"
    static let patrol = "DesktopPet.settings.patrol"
    static let scale = "DesktopPet.settings.petScale"
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isClickThroughEnabled: Bool
    @Published var isPatrolEnabled: Bool
    @Published var petScale: Double

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

        if defaults.object(forKey: SettingsKeys.scale) == nil {
            petScale = 1.0
        } else {
            petScale = defaults.double(forKey: SettingsKeys.scale)
        }

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
    }
}
