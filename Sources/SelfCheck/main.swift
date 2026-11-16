import Foundation
import SMNCore

// Run with: swift run SelfCheck

// CAP with prefix (short-term notice) and default namespace (alert) both parse.
let prefixed = """
<?xml version="1.0" encoding="UTF-8"?><cap:alert xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2">
<cap:identifier>id-1</cap:identifier><cap:info><cap:event>TORMENTAS FUERTES</cap:event><cap:severity>Severe</cap:severity>
<cap:expires>2026-11-16T16:43:00-03:00</cap:expires>
<cap:headline>AVISO NARANJA POR TORMENTAS</cap:headline>
<cap:area><cap:polygon>-33.72,-64.87 -33.93,-65.76 -33.30,-65.84 -33.07,-64.96 -33.72,-64.87</cap:polygon></cap:area>
</cap:info></cap:alert>
"""
let a = CAPParser.parse(Data(prefixed.utf8))!
assert(a.identifier == "id-1" && a.level == "naranja" && a.polygons.count == 1)
assert(a.contains(lat: -33.5, lon: -65.3))      // inside
assert(!a.contains(lat: -33.13, lon: -64.35))   // Río Cuarto city is just outside this polygon
assert(a.isActive(at: ISO8601DateFormatter().date(from: "2026-11-16T16:00:00-03:00")!))
assert(!a.isActive(at: ISO8601DateFormatter().date(from: "2026-11-16T17:00:00-03:00")!))

let plain = """
<?xml version="1.0"?><alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>id-2</identifier>
<info><event>Tormentas</event><severity>Moderate</severity><headline>Tormentas</headline>
<description>Lluvia &#xE1;</description><area><areaDesc></areaDesc><polygon>0,0 0,1 1,1 1,0 0,0</polygon></area></info></alert>
"""
let b = CAPParser.parse(Data(plain.utf8))!
assert(b.level == "amarillo" && b.description == "Lluvia á" && b.contains(lat: 0.5, lon: 0.5))
assert(CAPParser.parse(Data("<html></html>".utf8)) == nil)

// Feed scraping dedupes and ignores other links.
let html = #"<a href="https://ssl.smn.gob.ar/feeds/CAP/x/1.xml">a</a><a href="https://ssl.smn.gob.ar/feeds/CAP/x/1.xml">b</a><a href="https://evil.com/feeds/CAP/2.xml">c</a>"#
assert(capLinks(inFeedHTML: html).map(\.lastPathComponent) == ["1.xml"])

// Risk windows group consecutive hours and merge reasons.
let json = """
{"utc_offset_seconds":-10800,"hourly":{
 "time":["2026-11-16T14:00","2026-11-16T15:00","2026-11-16T16:00","2026-11-16T17:00","2026-11-16T18:00","2026-11-16T19:00"],
 "precipitation":[0,5,0.5,0,3,null],"precipitation_probability":[0,90,80,0,70,null],
 "wind_gusts_10m":[10,20,60,10,10,null],"weather_code":[1,95,3,1,61,null],"snowfall":[0,0,0,0,0,null]}}
"""
let f = try! JSONDecoder().decode(HourlyForecast.self, from: Data(json.utf8))
let from = ISO8601DateFormatter().date(from: "2026-11-16T14:30:00-03:00")!
let w = riskWindows(f, from: from, to: from.addingTimeInterval(24 * 3600))
assert(w.count == 2, "\(w)")
assert(w[0].reasons == ["tormenta", "lluvia fuerte", "ráfagas"])
assert(w[0].end.timeIntervalSince(w[0].start) == 2 * 3600)   // 15:00–17:00
assert(w[1].reasons == ["lluvia fuerte"])
let text = report(w, timeZone: TimeZone(secondsFromGMT: -10800)!)
assert(text.contains("15:00–17:00") && text.contains("18:00–19:00"), text)
print(text)

// Notify once per event; re-notify only when the level rises or the event comes back.
func alert(_ id: String, _ event: String, _ severity: String) -> CAPAlert {
    var x = CAPAlert(); x.identifier = id; x.event = event; x.severity = severity
    x.url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/xml_generados/CAP_1_Tormenta_Llanura_alertas_alertas_\(id).xml")
    return x
}
var r = alertsToNotify(active: [alert("1", "Tormentas", "Moderate"), alert("2", "Tormentas", "Moderate")], previous: [:])
assert(r.notify.count == 1 && r.state == ["TORMENTAS": 1])
r = alertsToNotify(active: [alert("3", "Tormentas", "Moderate")], previous: r.state)   // SMN update, new id
assert(r.notify.isEmpty)
r = alertsToNotify(active: [alert("4", "Tormentas", "Severe")], previous: r.state)     // escalation
assert(r.notify.map(\.identifier) == ["4"] && r.state == ["TORMENTAS": 2])
r = alertsToNotify(active: [], previous: r.state)                                        // ended
assert(r.state.isEmpty)
r = alertsToNotify(active: [alert("5", "Tormentas", "Moderate")], previous: r.state)   // back again
assert(r.notify.count == 1)
var acp = alert("6", "TORMENTAS", "Severe")
acp.url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/avisocortoplazo/2026_11_16_1622_cap_es.xml")
r = alertsToNotify(active: [alert("7", "Tormentas", "Moderate"), acp], previous: ["TORMENTAS": 1])
assert(r.notify.map(\.identifier) == ["6"])                                              // short-term notice is separate

// Menu bar icon: phenomenon of the worst alert; short-term notices get the warning triangle.
assert(menuBarIcon(for: []) == ("cloud.sun", nil))
var stormHail = alert("8", "Tormentas", "Moderate"); stormHail.description = "ocasional granizo"
assert(menuBarIcon(for: [stormHail]) == ("cloud.bolt.rain", "amarillo"))
assert(menuBarIcon(for: [stormHail, alert("9", "Viento", "Severe")]) == ("wind", "naranja"))
var acpHail = acp; acpHail.headline = "AVISO NARANJA POR TORMENTAS CON CAIDA DE GRANIZO"
assert(menuBarIcon(for: [alert("10", "Viento", "Severe"), acpHail]) == ("exclamationmark.triangle.fill", "naranja"))  // tie -> short-term
assert(menuBarIcon(for: [alert("14", "Granizo raro", "Moderate")]).symbol == "cloud")                             // unknown event
assert(menuBarIcon(for: [alert("11", "Viento Zonda", "Moderate")]).symbol == "wind")
assert(menuBarIcon(for: [alert("12", "Nevadas", "Moderate")]).symbol == "snowflake")
assert(menuBarIcon(for: [alert("13", "Lluvias", "Moderate")]).symbol == "cloud.heavyrain")

assert(capRegion(alert("1", "", "").url!) == "Llanura")
assert(capRegion(acp.url!) == nil)
print("SelfCheck OK")
