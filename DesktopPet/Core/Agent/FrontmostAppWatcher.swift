//
// FrontmostAppWatcher.swift
// 监听前台应用变化（用于「前台应用」类触发器）。
//

import AppKit
import Combine

@MainActor
final class FrontmostAppWatcher: ObservableObject {
    @Published private(set) var frontmostLocalizedName: String = ""

    private var cancellable: AnyCancellable?

    func start() {
        refresh()
        cancellable = NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }

    private func refresh() {
        frontmostLocalizedName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }
}
