import Foundation
@testable import SMNCore

let riocuarto = Coordinate(lat: -33.13, lon: -64.35)

/// A square polygon of ±0.5° around `center`, as CAP writes it ("lat,lon lat,lon ...").
func square(around c: Coordinate) -> String {
    let (a, b, d, e) = (c.lat - 0.5, c.lat + 0.5, c.lon - 0.5, c.lon + 0.5)
    return "\(a),\(d) \(a),\(e) \(b),\(e) \(b),\(d) \(a),\(d)"
}

func capXML(id: String, event: String = "Tormentas", severity: String = "Moderate", headline: String = "",
            expires: String = "2099-01-01T00:00:00-03:00", around center: Coordinate = riocuarto) -> Data {
    Data("""
    <?xml version="1.0"?><alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>\(id)</identifier>
    <info><event>\(event)</event><severity>\(severity)</severity><headline>\(headline)</headline>
    <expires>\(expires)</expires><area><polygon>\(square(around: center))</polygon></area></info></alert>
    """.utf8)
}

func capURL(_ name: String, shortTerm: Bool = false, region: String = "Llanura") -> URL {
    shortTerm
        ? URL(string: "https://ssl.smn.gob.ar/feeds/CAP/avisocortoplazo/\(name).xml")!
        : URL(string: "https://ssl.smn.gob.ar/feeds/CAP/xml_generados/CAP_1_Tormenta_\(region)_alertas_alertas_\(name).xml")!
}

func rss(_ urls: [URL]) -> Data {
    Data(("<rss><channel>" + urls.map { "<item><link>\($0)</link></item>" }.joined() + "</channel></rss>").utf8)
}

/// Serves canned responses and records every request.
actor FakeHTTP: HTTPClient {
    var responses: [URL: Data] = [:]
    var failing: Set<URL> = []
    private(set) var requests: [URL] = []

    func set(_ url: URL, _ data: Data) { responses[url] = data }
    func fail(_ url: URL) { failing.insert(url) }
    func heal(_ url: URL) { failing.remove(url) }
    func clearLog() { requests = [] }

    func data(from url: URL) async throws -> Data {
        requests.append(url)
        if failing.contains(url) { throw FetchError.status(429) }
        if let d = responses[url] { return d }
        if url.host == "api.open-meteo.com" { throw FetchError.status(503) }   // forecast is optional
        throw FetchError.status(404)
    }
}

final class MemoryStore: CAPStore, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: Data] = [:]

    func load(_ url: URL) -> Data? { lock.withLock { files[url] } }
    func save(_ data: Data, for url: URL) { lock.withLock { files[url] = data } }
    func prune(keeping urls: [URL]) { lock.withLock { files = files.filter { urls.contains($0.key) } } }
    var count: Int { lock.withLock { files.count } }
}

func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "SMNCoreTests-\(UUID().uuidString)")!
}

func alert(_ id: String, _ event: String, _ severity: String, shortTerm: Bool = false) -> CAPAlert {
    var a = CAPAlert()
    a.identifier = id
    a.event = event
    a.severity = severity
    a.url = capURL(id, shortTerm: shortTerm)
    return a
}
