import AppKit
import Foundation

@MainActor
final class MouseTracker {
    private var timer: Timer?
    /// When false (e.g. pet hidden), sampling still runs but does not emit interactions — avoids stale wakeups off-screen.
    var interactionSamplingEnabled = true
    var onInteraction: ((InteractionEvent) -> Void)?
    var petFrameProvider: (() -> CGRect?)?
    private var lastLocation: CGPoint = .zero
    private var lastHoverEmit: TimeInterval = 0
    private let hoverThrottle: TimeInterval = 0.25

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
        guard interactionSamplingEnabled else {
            lastLocation = current
            return
        }
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
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastHoverEmit >= hoverThrottle {
                    lastHoverEmit = now
                    onInteraction?(.mouseHoverNear(distance: distance))
                }
            }
        }
    }
}
