import Foundation

/// Alerts covering one of the user's cities.
public struct Place: Identifiable, Sendable {
    public let city: City
    public var alerts: [CAPAlert]
    public var forecast: HourlyForecast?
    public var current: CurrentWeather?
    public var id: String { city.id }

    public init(city: City, alerts: [CAPAlert], forecast: HourlyForecast? = nil, current: CurrentWeather? = nil) {
        self.city = city
        self.alerts = alerts
        self.forecast = forecast
        self.current = current
    }
}

/// Something worth telling the user after a check.
public enum Notice: Equatable, Sendable {
    /// A new alert, or the same phenomenon at a higher level.
    case new(CAPAlert, city: City)
    /// The phenomenon moves to a higher level within the hour ("a las 02:10 pasa a naranja").
    case escalation(event: String, to: AlertLevel, at: Date, city: City)
    /// A phenomenon the user was told about is no longer in force.
    case ended(event: String, level: AlertLevel, city: City)

    public var alert: CAPAlert? { if case .new(let a, _) = self { a } else { nil } }
    public var level: AlertLevel {
        switch self {
        case .new(let a, _): a.level
        case .escalation(_, let l, _, _), .ended(_, let l, _): l
        }
    }
}

/// What has already been announced, so each check only tells what changed.
/// Level keys are "<city name>|<event key>"; escalation keys also carry level and start time.
public struct NoticeState: Equatable, Sendable {
    public var levels: [String: AlertLevel] = [:]
    public var escalations: Set<String> = []
    public init(levels: [String: AlertLevel] = [:], escalations: Set<String> = []) {
        self.levels = levels
        self.escalations = escalations
    }
}

/// How long before a level change the user gets the heads-up.
public let escalationLead: TimeInterval = 3600

/// Decides the notices for this check. `partial`: some zones aren't downloaded yet, so a missing
/// alert may just be pending; nothing is reported as ended and previous state is kept.
public func planNotices(places: [Place], previous: NoticeState, now: Date, partial: Bool)
    -> (notices: [Notice], state: NoticeState) {
    var notices: [Notice] = []
    var state = NoticeState()
    for place in places {
        let prefix = place.city.name + "|"
        let before = Dictionary(uniqueKeysWithValues: previous.levels.compactMap { k, v in
            k.hasPrefix(prefix) ? (String(k.dropFirst(prefix.count)), v) : nil
        })
        let (fresh, levels) = alertsToNotify(active: place.alerts, previous: before)
        notices += fresh.map { .new($0, city: place.city) }
        for (k, v) in levels { state.levels[prefix + k] = v }
        if !partial {
            for (k, level) in before where levels[k] == nil {
                let event = sentenceCased(k.hasPrefix("ACP:") ? String(k.dropFirst(4)) : k)
                notices.append(.ended(event: event, level: level, city: place.city))
            }
        }
        let justAnnounced = Set(fresh.map(\.eventKey))
        for group in groupAlerts(place.alerts) where !group.isShortTerm {
            let steps = group.timeline
            for i in steps.indices.dropFirst() where steps[i].level > steps[i - 1].level {
                guard let start = steps[i - 1].until, start > now, start.timeIntervalSince(now) <= escalationLead
                else { continue }
                let key = "\(prefix)\(group.id)|\(steps[i].level.rawValue)|\(Int(start.timeIntervalSince1970))"
                state.escalations.insert(key)
                // The arrival notice already said "naranja"; don't repeat it in the same minute.
                guard !previous.escalations.contains(key), !justAnnounced.contains(group.id) else { continue }
                notices.append(.escalation(event: group.worst.displayEvent, to: steps[i].level, at: start, city: place.city))
            }
        }
    }
    if partial {
        state.levels.merge(previous.levels) { current, _ in current }
        state.escalations.formUnion(previous.escalations)
    }
    return (notices, state)
}
