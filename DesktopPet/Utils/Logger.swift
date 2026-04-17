import Foundation

final class Logger {
    static let shared = Logger()

    private init() {}

    func info(_ message: String) {
        print("[DesktopPet] \(message)")
    }
}
