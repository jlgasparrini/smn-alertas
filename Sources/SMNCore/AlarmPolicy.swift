import Foundation

/// How the app reacts to a new alert, from the user's settings.
public struct AlarmPolicy: Equatable, Sendable {
    public enum Reaction: Equatable, Sendable {
        case blinkOnly
        case sound(repeating: Bool)
    }

    public var soundEnabled = true
    public var repeatUntilSeen = true
    public var quietYellowAtNight = false
    /// Alerts below this level show in the panel but don't notify, blink or sound.
    public var minimumLevel = AlertLevel.yellow
    /// Night window for `quietYellowAtNight`, in local hours: [start, 24) ∪ [0, end).
    public var nightStartHour = 23
    public var nightEndHour = 7

    public init(soundEnabled: Bool = true, repeatUntilSeen: Bool = true, quietYellowAtNight: Bool = false,
                minimumLevel: AlertLevel = .yellow) {
        self.soundEnabled = soundEnabled
        self.repeatUntilSeen = repeatUntilSeen
        self.quietYellowAtNight = quietYellowAtNight
        self.minimumLevel = minimumLevel
    }

    public func announces(_ level: AlertLevel) -> Bool { level >= minimumLevel }

    public func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= nightStartHour || hour < nightEndHour
    }

    /// Orange and red always sound (if sound is on); yellow can stay quiet at night.
    public func reaction(to level: AlertLevel, at date: Date, calendar: Calendar = .current) -> Reaction {
        guard soundEnabled else { return .blinkOnly }
        if quietYellowAtNight, level == .yellow, isNight(date, calendar: calendar) { return .blinkOnly }
        return .sound(repeating: repeatUntilSeen)
    }
}
