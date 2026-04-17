import AppKit
import Foundation

@MainActor
final class MouseTracker {
    private var timer: Timer?
    var onInteraction: ((InteractionEvent) -> Void)?
    var petFrameProvider: (() -> CGRect?)?
    private var lastLocation: CGPoint = .zero

    func start() {
        guard timer == nil else { return }
        lastLocation = NSEvent.mouseLocation
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.sample()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Logger.shared.info("Mouse tracker started.")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Logger.shared.info("Mouse tracker stopped.")
    }

    private func sample() {
        let current = NSEvent.mouseLocation
        let dx = current.x - lastLocation.x
        let dy = current.y - lastLocation.y
        let speed = sqrt(dx * dx + dy * dy)
        lastLocation = current

        if speed > 80 {
            onInteraction?(.mouseMovedFast(speed: speed))
            return
        }

        if let frame = petFrameProvider?() {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let distance = hypot(current.x - center.x, current.y - center.y)
            if distance < 120 {
                onInteraction?(.mouseHoverNear(distance: distance))
            }
        }
    }
}
