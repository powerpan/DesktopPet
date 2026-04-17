import ApplicationServices
import Combine
import Foundation
import SwiftUI

@MainActor
final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isGranted: Bool

    init() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        isGranted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshStatus(prompt: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        guard granted != isGranted else { return }
        isGranted = granted
    }

    func requestIfNeeded() {
        refreshStatus(prompt: true)
    }
}
