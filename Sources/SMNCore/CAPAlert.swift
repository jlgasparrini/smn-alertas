import Foundation

public struct Coordinate: Hashable, Codable, Sendable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/// One SMN alert or short-term notice, parsed from a CAP 1.2 XML file.
public struct CAPAlert: Identifiable, Hashable, Sendable {
    public var identifier = ""
    public var event = ""
    public var headline = ""
    public var description = ""
    public var instruction = ""
    public var severity = ""
    public var areaDesc = ""
    public var onset: Date?
    public var expires: Date?
    public var polygons: [[Coordinate]] = []
    public var url: URL?

    public init() {}

    public var id: String { identifier }
    public var level: AlertLevel { AlertLevel(severity: severity, headline: headline) }
    /// "Aviso a muy corto plazo": the storm is already happening.
    public var isShortTerm: Bool { url?.path.contains("avisocortoplazo") == true }
    public var mentionsHail: Bool { (headline + " " + description).uppercased().contains("GRANIZO") }
    public var title: String { headline.isEmpty ? event : headline }
    /// "Alerta naranja" or, for short-term notices, "Aviso naranja".
    public var levelLabel: String { isShortTerm ? "Aviso \(level.name(feminine: false))" : "Alerta \(level.name())" }

    public func isActive(at now: Date) -> Bool { (expires ?? .distantFuture) > now }
    public func contains(_ point: Coordinate) -> Bool { polygons.contains { pointInPolygon(point, $0) } }

    /// SF Symbol for the phenomenon. Short-term notices get a filled warning triangle so they stand
    /// out from the outlined weather glyphs.
    public var symbolName: String {
        if isShortTerm { return "exclamationmark.triangle.fill" }
        let text = (event + " " + headline).uppercased()
        if text.contains("TORMENTA") { return "cloud.bolt.rain" }
        if text.contains("NEV") || text.contains("NIEVE") { return "snowflake" }
        if text.contains("VIENTO") || text.contains("ZONDA") { return "wind" }
        if text.contains("LLUVIA") { return "cloud.heavyrain" }
        return "cloud"
    }
}

/// The alert that should drive the icon: highest level; on a tie, the short-term notice.
public func mostSevere(_ alerts: [CAPAlert]) -> CAPAlert? {
    alerts.max { ($0.level, $0.isShortTerm ? 1 : 0) < ($1.level, $1.isShortTerm ? 1 : 0) }
}

/// Ray-casting test; polygons are small enough that lat/lon can be treated as planar.
func pointInPolygon(_ p: Coordinate, _ polygon: [Coordinate]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in polygon.indices {
        let a = polygon[i], b = polygon[j]
        if (a.lat > p.lat) != (b.lat > p.lat),
           p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon {
            inside.toggle()
        }
        j = i
    }
    return inside
}

/// SMN re-issues each alert with a new identifier on every update, so notify per event instead:
/// only when an event appears or its level rises. `previous` maps event key -> level last notified.
public func alertsToNotify(active: [CAPAlert], previous: [String: AlertLevel])
    -> (notify: [CAPAlert], state: [String: AlertLevel]) {
    var worst: [String: CAPAlert] = [:]
    for a in active {
        let key = (a.isShortTerm ? "ACP:" : "") + a.event.uppercased()
        if let w = worst[key], w.level >= a.level { continue }
        worst[key] = a
    }
    let state = worst.mapValues(\.level)
    let notify = worst.values.filter { a in
        let key = (a.isShortTerm ? "ACP:" : "") + a.event.uppercased()
        return previous[key].map { a.level > $0 } ?? true
    }
    return (notify.sorted { $0.level > $1.level }, state)
}
