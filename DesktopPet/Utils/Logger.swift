//
// Logger.swift
// 轻量日志：统一前缀输出到控制台，便于在 Xcode 控制台过滤 DesktopPet 相关行。
//

import Foundation

final class Logger {
    static let shared = Logger()

    private init() {}

    func info(_ message: String) {
        print("[DesktopPet] \(message)")
    }
}
