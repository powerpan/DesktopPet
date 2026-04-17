import CoreGraphics

enum InteractionEvent {
    case keyboardInput
    case mouseMoved(location: CGPoint, speed: CGFloat)
    case patrolRequested
    case idleTimeout
}
