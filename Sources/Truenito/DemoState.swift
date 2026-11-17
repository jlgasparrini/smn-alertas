#if DEV_TOOLS
import Foundation
import SMNCore

/// Simulated situations for "Probar estados" (development builds only):
/// icon, blinking, sound, notification and panel without a real alert.
struct DemoState {
    let title: String
    let event: String
    let severity: String
    var headline = ""
    var shortTerm = false
    var description = ""
    /// Reproduce the real 2026-11-16 case: one storm as two identical yellow files plus an orange one later.
    var splitLikeSMN = false
    /// Adds a second, calm city to show the panel with several cities.
    var otherCity = false
    var instruction = "1- Evitá salir. 2- Retirá objetos que puedan volarse. 3- Desconectá los electrodomésticos si ingresa agua."

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
        DemoState(title: "🟡→🟠 Tormenta en varios tramos (caso real)", event: "Tormentas", severity: "Moderate",
                  description: "El área será afectada por tormentas, algunas fuertes o puntualmente severas. Las mismas podrán estar acompañadas por fuertes precipitaciones en cortos períodos, frecuente actividad eléctrica, ocasional granizo y ráfagas intensas. Se esperan valores de precipitación acumulada entre 30 y 70 mm, que pueden ser superados en forma puntual.",
                  splitLikeSMN: true),
        DemoState(title: "🏙️ Dos ciudades, alerta en una", event: "Viento Zonda", severity: "Severe",
                  description: "Ráfagas de hasta 90 km/h.", otherCity: true),
        DemoState(title: "⚠️ Aviso naranja a corto plazo (granizo)", event: "TORMENTAS FUERTES", severity: "Severe",
                  headline: "AVISO NARANJA POR TORMENTAS FUERTES CON CAIDA DE GRANIZO", shortTerm: true,
                  description: "TORMENTAS FUERTES CON CAIDA DE GRANIZO",
                  instruction: "Retirá objetos sueltos. Cerrá y alejate de ventanas. Permanecé en lugares cerrados."),
    ]

    func alerts(now: Date) -> [CAPAlert] {
        guard var first = alert(now: now) else { return [] }
        guard splitLikeSMN else { return [first] }
        first.expires = now.addingTimeInterval(2 * 3600)
        var twin = first
        twin.identifier = "demo-\(UUID().uuidString)"
        var later = first
        later.identifier = "demo-\(UUID().uuidString)"
        later.severity = "Severe"
        later.expires = now.addingTimeInterval(8 * 3600)
        return [later, first, twin]
    }

    private func alert(now: Date) -> CAPAlert? {
        guard !event.isEmpty else { return nil }
        var a = CAPAlert()
        a.identifier = "demo-\(UUID().uuidString)"
        a.event = event
        a.headline = headline.isEmpty ? event : headline
        a.severity = severity
        a.description = description
        a.instruction = instruction
        a.expires = now.addingTimeInterval(shortTerm ? 3600 : 9 * 3600)
        a.url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/" + (shortTerm ? "avisocortoplazo/demo.xml" : "xml_generados/demo.xml"))
        return a
    }

    /// A plausible next 24 h: rain building up 2–5 h from now with storms and gusts.
    func hours(now: Date) -> [HourPoint] {
        let start = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let rain: [Double] = [0, 0.4, 2.5, 7, 12, 6, 1.5, 0.3] + Array(repeating: 0, count: 10) + [0.5, 1.2, 0.4, 0, 0, 0]
        return rain.enumerated().map { i, mm in
            HourPoint(date: start.addingTimeInterval(Double(i) * 3600), precipitation: mm,
                      gust: (3...5).contains(i) ? 70 : 25, weatherCode: (3...5).contains(i) ? 95 : nil,
                      snowfall: event.uppercased().contains("NEV") && mm > 0 ? 1 : 0)
        }
    }
}
#endif
