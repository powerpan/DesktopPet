import ApplicationServices
import Foundation
import SwiftUI

@MainActor
final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isGranted: Bool = false
    var onStatusChanged: ((Bool) -> Void)?

    func refreshStatus(prompt: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        guard granted != isGranted else { return }
        isGranted = granted
        onStatusChanged?(granted)
    }

    func requestIfNeeded() {
        refreshStatus(prompt: true)
    }
}
