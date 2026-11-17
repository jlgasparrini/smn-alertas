import Foundation

/// ssl.smn.gob.ar/CAP/AR.php serves RSS to apps and an HTML view to browsers; both list the CAP XML URLs.
private let capLinkPattern = try! NSRegularExpression(pattern: #"(https://ssl\.smn\.gob\.ar/feeds/CAP/[^"<\s]+\.xml)"#)

public func capLinks(in feed: String) -> [URL] {
    var seen = Set<String>()
    return capLinkPattern.matches(in: feed, range: NSRange(feed.startIndex..., in: feed)).compactMap { m in
        let s = String(feed[Range(m.range(at: 1), in: feed)!])
        return seen.insert(s).inserted ? URL(string: s) : nil
    }
}

/// Region in alert file names, e.g. CAP_20261116125045_Tormenta_Llanura_alertas_alertas_18.xml -> "Llanura".
public func capRegion(_ url: URL) -> String? {
    let parts = url.lastPathComponent.split(separator: "_")
    return parts.first == "CAP" && parts.count > 3 ? String(parts[3]) : nil
}

/// Parses a CAP 1.2 document. SMN serves it both with a `cap:` prefix and as the default namespace.
public final class CAPParser: NSObject, XMLParserDelegate {
    private var alert = CAPAlert()
    private var text = ""
    private var sawInfo = false
    private let iso = ISO8601DateFormatter()

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
        case "onset": alert.onset = iso.date(from: value)
        case "expires": alert.expires = iso.date(from: value)
        case "polygon":
            let points = value.split(separator: " ").compactMap { pair -> Coordinate? in
                let p = pair.split(separator: ",")
                guard p.count == 2, let lat = Double(p[0]), let lon = Double(p[1]) else { return nil }
                return Coordinate(lat: lat, lon: lon)
            }
            if points.count >= 3 { alert.polygons.append(points) }
        default: break
        }
        text = ""
    }
}
