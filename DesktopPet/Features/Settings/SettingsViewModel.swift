import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isClickThroughEnabled = true
    @Published var isPatrolEnabled = true
    @Published var petScale: Double = 1.0
}
