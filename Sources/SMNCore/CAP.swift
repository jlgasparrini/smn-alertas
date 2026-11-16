import Foundation

/// One SMN alert or short-term notice, parsed from a CAP 1.2 XML file.
public struct CAPAlert: Equatable {
    public var identifier = ""
    public var event = ""
    public var headline = ""
    public var description = ""
    public var instruction = ""
    public var severity = ""
    public var areaDesc = ""
    public var onset: Date?
    public var expires: Date?
    public var polygons: [[(lat: Double, lon: Double)]] = []
    public var url: URL?

    public init() {}

    public static func == (a: CAPAlert, b: CAPAlert) -> Bool { a.identifier == b.identifier }

    /// SMN colour level, derived from the CAP severity (the headline wins when it names a colour).
    public var level: String {
        let h = headline.uppercased()
        if h.contains("ROJ") { return "rojo" }
        if h.contains("NARANJA") { return "naranja" }
        if h.contains("AMARILL") { return "amarillo" }
        switch severity {
        case "Extreme": return "rojo"
        case "Severe": return "naranja"
        default: return "amarillo"
        }
    }

    public var emoji: String { ["rojo": "🔴", "naranja": "🟠"][level] ?? "🟡" }

    public func isActive(at now: Date) -> Bool { (expires ?? .distantFuture) > now }

    public func contains(lat: Double, lon: Double) -> Bool {
        polygons.contains { pointInPolygon(lat: lat, lon: lon, polygon: $0) }
    }
}

/// Ray-casting test; polygons are small enough that lat/lon can be treated as planar.
public func pointInPolygon(lat: Double, lon: Double, polygon: [(lat: Double, lon: Double)]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in polygon.indices {
        let a = polygon[i], b = polygon[j]
        if (a.lat > lat) != (b.lat > lat),
           lon < (b.lon - a.lon) * (lat - a.lat) / (b.lat - a.lat) + a.lon {
            inside.toggle()
        }
        j = i
    }
    return inside
}

/// Parses a CAP 1.2 document. SMN serves it both with a `cap:` prefix and as the default namespace.
public final class CAPParser: NSObject, XMLParserDelegate {
    private var alert = CAPAlert()
    private var text = ""
    private var sawInfo = false

    public static func parse(_ data: Data, url: URL? = nil) -> CAPAlert? {
        let delegate = CAPParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), delegate.sawInfo else { return nil }
        delegate.alert.url = url
        return delegate.alert
    }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                       qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "info" { sawInfo = true }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "identifier": alert.identifier = value
        case "event": alert.event = value
        case "headline": alert.headline = value
        case "description": alert.description = value
        case "instruction": alert.instruction = value
        case "severity": alert.severity = value
        case "areaDesc": alert.areaDesc = value
        case "onset": alert.onset = Self.date(value)
        case "expires": alert.expires = Self.date(value)
        case "polygon":
            let points = value.split(separator: " ").compactMap { pair -> (lat: Double, lon: Double)? in
                let p = pair.split(separator: ",")
                guard p.count == 2, let la = Double(p[0]), let lo = Double(p[1]) else { return nil }
                return (la, lo)
            }
            if points.count >= 3 { alert.polygons.append(points) }
        default: break
        }
        text = ""
    }

    static func date(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }
}

public func levelRank(_ level: String) -> Int { ["amarillo": 1, "naranja": 2, "rojo": 3][level] ?? 0 }

/// SMN re-issues each alert with a new identifier on every update, so notify per event instead:
/// only when an event appears or its level rises. `previous` maps event key -> highest level rank last time.
public func alertsToNotify(active: [CAPAlert], previous: [String: Int]) -> (notify: [CAPAlert], state: [String: Int]) {
    var worst: [String: CAPAlert] = [:]
    for a in active {
        let key = (a.url?.path.contains("avisocortoplazo") == true ? "ACP:" : "") + a.event.uppercased()
        if let w = worst[key], levelRank(w.level) >= levelRank(a.level) { continue }
        worst[key] = a
    }
    let state = worst.mapValues { levelRank($0.level) }
    let notify = worst.filter { state[$0.key]! > (previous[$0.key] ?? 0) }.map(\.value)
    return (notify.sorted { levelRank($0.level) > levelRank($1.level) }, state)
}

extension CAPAlert {
    public var isShortTerm: Bool { url?.path.contains("avisocortoplazo") == true }
    public var mentionsHail: Bool { (headline + " " + description).uppercased().contains("GRANIZO") }
}

/// Menu bar icon for the current situation: SF Symbol of the worst alert's phenomenon plus its level.
/// Short-term notices (it's happening now) get a filled warning triangle so they stand out from the outlined weather glyphs.
public func menuBarIcon(for active: [CAPAlert]) -> (symbol: String, level: String?) {
    guard let worst = active.max(by: {
        (levelRank($0.level), $0.isShortTerm ? 1 : 0) < (levelRank($1.level), $1.isShortTerm ? 1 : 0)
    }) else { return ("cloud.sun", nil) }
    let text = (worst.event + " " + worst.headline).uppercased()
    let symbol: String
    if worst.isShortTerm { symbol = "exclamationmark.triangle.fill" }
    else if text.contains("TORMENTA") { symbol = "cloud.bolt.rain" }
    else if text.contains("NEV") || text.contains("NIEVE") { symbol = "snowflake" }
    else if text.contains("VIENTO") || text.contains("ZONDA") { symbol = "wind" }
    else if text.contains("LLUVIA") { symbol = "cloud.heavyrain" }
    else { symbol = "cloud" }
    return (symbol, worst.level)
}

/// Region in alert file names, e.g. CAP_20261116125045_Tormenta_Llanura_alertas_alertas_18.xml -> "Llanura".
public func capRegion(_ url: URL) -> String? {
    let parts = url.lastPathComponent.split(separator: "_")
    return parts.first == "CAP" && parts.count > 3 ? String(parts[3]) : nil
}

/// ssl.smn.gob.ar/CAP/AR.php serves RSS to apps and an HTML view to browsers; both list the CAP XML URLs.
public func capLinks(inFeedHTML html: String) -> [URL] {
    let regex = try! NSRegularExpression(pattern: #"(https://ssl\.smn\.gob\.ar/feeds/CAP/[^"<\s]+\.xml)"#)
    let range = NSRange(html.startIndex..., in: html)
    var seen = Set<String>()
    return regex.matches(in: html, range: range).compactMap { m in
        let s = String(html[Range(m.range(at: 1), in: html)!])
        return seen.insert(s).inserted ? URL(string: s) : nil
    }
}
