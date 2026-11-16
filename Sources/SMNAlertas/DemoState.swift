import Foundation
import SMNCore

/// Simulated situations for "Probar estados": icon, blinking, sound and notification without a real alert.
struct DemoState {
    let title: String
    let event: String
    let severity: String
    var headline = ""
    var shortTerm = false
    var description = ""

    static let all: [DemoState] = [
        DemoState(title: "Sin alertas", event: "", severity: ""),
        DemoState(title: "🟡 Alerta amarilla por tormentas", event: "Tormentas", severity: "Moderate",
                  description: "Tormentas aisladas, algunas fuertes, con ocasional caída de granizo."),
        DemoState(title: "🟡 Alerta amarilla por nevadas", event: "Nevadas", severity: "Moderate",
                  description: "Nevadas de variada intensidad."),
        DemoState(title: "🟠 Alerta naranja por lluvias", event: "Lluvias", severity: "Severe",
                  description: "Lluvias intensas, acumulados de 70 a 100 mm."),
        DemoState(title: "🟠 Alerta naranja por viento zonda", event: "Viento Zonda", severity: "Severe",
                  description: "Ráfagas de hasta 90 km/h."),
        DemoState(title: "🔴 Alerta roja por tormentas", event: "Tormentas", severity: "Extreme",
                  description: "Tormentas severas con lluvias intensas."),
        DemoState(title: "⚠️ Aviso naranja a corto plazo (granizo)", event: "TORMENTAS FUERTES", severity: "Severe",
                  headline: "AVISO NARANJA POR TORMENTAS FUERTES CON CAIDA DE GRANIZO", shortTerm: true,
                  description: "Tormentas fuertes con caída de granizo."),
    ]

    func alert(now: Date = Date()) -> CAPAlert? {
        guard !event.isEmpty else { return nil }
        var a = CAPAlert()
        a.identifier = "demo-\(UUID().uuidString)"
        a.event = event
        a.headline = headline.isEmpty ? event : headline
        a.severity = severity
        a.description = description
        a.expires = now.addingTimeInterval(3 * 3600)
        a.url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/" + (shortTerm ? "avisocortoplazo/demo.xml" : "xml_generados/demo.xml"))
        return a
    }

    func report(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:00"
        f.locale = Locale(identifier: "es_AR")
        let start = now.addingTimeInterval(3600), end = start.addingTimeInterval(2 * 3600)
        return "(Prueba) Horarios con más cuidado:\n🕒 \(f.string(from: start))–\(f.string(from: end).suffix(5)) — \(event.lowercased())"
    }
}
