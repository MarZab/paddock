import Foundation

/// When hands-free turns itself off (backlog doc Voice, Hands-free): it is the one case where the
/// microphone opens without a key press, so it does not stay on for ever. It ends after a time
/// without the operator speaking, and when Paddock goes to the background unless the operator chose
/// to keep it. It is not remembered across launches.
public struct HandsFreeLimits: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case idle(minutes: Int)
        case background

        public var message: String {
            switch self {
            case .idle(let minutes): "Hands-free turned itself off: no speech for \(minutes) min"
            case .background: "Hands-free turned itself off: Paddock went to the background"
            }
        }
    }

    public static let defaultIdleMinutes = 20
    public static let maxIdleMinutes = 240

    /// Minutes without speech before hands-free ends; nil means never.
    public let idleMinutes: Int?
    public let keepInBackground: Bool

    /// `idleMinutes` of 0 or less means never; more than `maxIdleMinutes` is cut to it.
    public init(idleMinutes: Int, keepInBackground: Bool) {
        self.idleMinutes = idleMinutes > 0 ? min(idleMinutes, Self.maxIdleMinutes) : nil
        self.keepInBackground = keepInBackground
    }

    /// Why hands-free must end now, or nil. `idleFor` is the time since the operator last spoke (or
    /// since hands-free was turned on, or Listen was used).
    public func reason(idleFor: TimeInterval, appActive: Bool) -> Reason? {
        if !appActive && !keepInBackground { return .background }
        if let idleMinutes, idleFor >= TimeInterval(idleMinutes) * 60 { return .idle(minutes: idleMinutes) }
        return nil
    }
}
