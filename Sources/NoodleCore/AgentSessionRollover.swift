import Foundation

/// When an idle bot's harness session is replaced with a fresh one. The workspace,
/// memory and messages stay; only the model's running context starts over.
public struct AgentSessionRollover: Equatable, Sendable {
    public static let ageDefaultsKey = "Noodle.session.rolloverAge"
    public static let idleDefaultsKey = "Noodle.session.rolloverIdle"
    public static let defaultAge: TimeInterval = 24 * 60 * 60
    public static let defaultIdle: TimeInterval = 60 * 60
    /// Zero keeps a session until someone starts a new one.
    public static let ageOptions: [TimeInterval] = [0, 24 * 60 * 60, 3 * 24 * 60 * 60, 7 * 24 * 60 * 60]
    public static let idleOptions: [TimeInterval] = [30 * 60, 60 * 60, 2 * 60 * 60, 4 * 60 * 60]

    public let age: TimeInterval
    public let idle: TimeInterval

    public init(age: TimeInterval = defaultAge, idle: TimeInterval = defaultIdle) {
        self.age = max(0, age)
        self.idle = max(60, idle)
    }

    public var isEnabled: Bool { age > 0 }

    public static func load(from defaults: UserDefaults) -> Self {
        Self(age: defaults.object(forKey: ageDefaultsKey) as? TimeInterval ?? defaultAge,
             idle: defaults.object(forKey: idleDefaultsKey) as? TimeInterval ?? defaultIdle)
    }

    public func isDue(sessionStarted: Date, lastInteraction: Date, at now: Date) -> Bool {
        isEnabled && now.timeIntervalSince(sessionStarted) >= age && now.timeIntervalSince(lastInteraction) >= idle
    }

    public static func ageName(_ age: TimeInterval) -> String {
        switch age {
        case ..<1: "Never"
        case 24 * 60 * 60: "Daily"
        case 7 * 24 * 60 * 60: "Weekly"
        default: "Every \(Int(age / (24 * 60 * 60))) days"
        }
    }

    public static func idleName(_ idle: TimeInterval) -> String {
        let minutes = Int(idle / 60)
        if minutes < 60 { return "\(minutes) minutes" }
        return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }
}
