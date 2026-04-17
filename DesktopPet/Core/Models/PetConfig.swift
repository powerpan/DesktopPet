import CoreGraphics

struct PetConfig {
    var windowSize: CGSize
    var patrolInterval: TimeInterval
    var idleToSleepInterval: TimeInterval

    static let `default` = PetConfig(
        windowSize: CGSize(width: 220, height: 220),
        patrolInterval: 12,
        idleToSleepInterval: 180
    )
}
