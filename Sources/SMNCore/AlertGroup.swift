import Foundation

/// All active alerts for one phenomenon. SMN splits a storm into several files by time slot and
/// zone ("amarilla hasta 20:59", "naranja hasta 02:59"), so the panel shows one row per group.
public struct AlertGroup: Identifiable, Sendable {
    public struct Step: Equatable, Sendable {
        public let level: AlertLevel
        public let until: Date?
    }

    public let alerts: [CAPAlert]         // sorted by expiry

    public var id: String { (worst.isShortTerm ? "ACP:" : "") + worst.event.uppercased() }
    public var worst: CAPAlert { mostSevere(alerts)! }
    public var isShortTerm: Bool { worst.isShortTerm }
    public var mentionsHail: Bool { alerts.contains(where: \.mentionsHail) }
    /// Level in force now: the first step of the timeline (expired alerts are already filtered out).
    public var current: AlertLevel { timeline.first?.level ?? worst.level }

    /// Levels in time order, consecutive repeats merged: [amarilla hasta 20:59, naranja hasta 02:59].
    public var timeline: [Step] {
        var steps: [Step] = []
        for a in alerts {
            if let last = steps.last, last.level == a.level { steps[steps.count - 1] = Step(level: a.level, until: a.expires) }
            else { steps.append(Step(level: a.level, until: a.expires)) }
        }
        return steps
    }
}

/// Groups alerts by phenomenon (short-term notices apart), most urgent first:
/// notices happening now, then the highest level, then the one ending soonest.
public func groupAlerts(_ alerts: [CAPAlert]) -> [AlertGroup] {
    let byKey = Dictionary(grouping: alerts) { ($0.isShortTerm ? "ACP:" : "") + $0.event.uppercased() }
    return byKey.values
        .map { AlertGroup(alerts: $0.sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }) }
        .sorted { a, b in
            let ka = (a.isShortTerm ? 1 : 0, a.worst.level), kb = (b.isShortTerm ? 1 : 0, b.worst.level)
            if ka != kb { return ka > kb }
            return (a.alerts.first?.expires ?? .distantFuture) < (b.alerts.first?.expires ?? .distantFuture)
        }
}
