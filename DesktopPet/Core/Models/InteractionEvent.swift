import CoreGraphics

enum InteractionEvent {
    case keyboardInput
    case mouseMovedFast(speed: CGFloat)
    case mouseHoverNear(distance: CGFloat)
    case patrolRequested
    case idleTimeout
}
