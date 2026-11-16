import Foundation

/// Hourly forecast from Open-Meteo (free, no key).
public struct HourlyForecast: Decodable {
    public struct Hourly: Decodable {
        public let time: [String]
        public let precipitation: [Double?]
        public let precipitation_probability: [Int?]
        public let wind_gusts_10m: [Double?]
        public let weather_code: [Int?]
        public let snowfall: [Double?]
    }
    public let hourly: Hourly
    public let utc_offset_seconds: Int

    public static func url(lat: Double, lon: Double) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=precipitation,precipitation_probability,wind_gusts_10m,weather_code,snowfall"
            + "&timezone=auto&forecast_days=3")!
    }
}

public struct RiskWindow: Equatable {
    public let start: Date
    public let end: Date          // exclusive: start of the hour after the last risky one
    public let reasons: [String]
}

/// Thresholds for "be careful" hours. Rough, conservative values.
let thunderCodes = 95...99        // WMO weather codes for thunderstorms
let heavyRainMM = 2.0
let strongGustKMH = 50.0

/// Groups consecutive risky hours between `from` and `to` into windows.
public func riskWindows(_ f: HourlyForecast, from: Date, to: Date) -> [RiskWindow] {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
    fmt.timeZone = TimeZone(secondsFromGMT: f.utc_offset_seconds)
    let h = f.hourly
    var windows: [RiskWindow] = []
    var current: (start: Date, end: Date, reasons: [String])?

    func close() {
        if let c = current { windows.append(RiskWindow(start: c.start, end: c.end, reasons: c.reasons)) }
        current = nil
    }

    for i in h.time.indices {
        guard let t = fmt.date(from: h.time[i]) else { continue }
        let hourEnd = t.addingTimeInterval(3600)
        guard hourEnd > from, t < to else { continue }

        var reasons: [String] = []
        if let c = h.weather_code[safe: i] ?? nil, thunderCodes.contains(c) { reasons.append("tormenta") }
        if let p = h.precipitation[safe: i] ?? nil, p >= heavyRainMM { reasons.append("lluvia fuerte") }
        if let g = h.wind_gusts_10m[safe: i] ?? nil, g >= strongGustKMH { reasons.append("ráfagas") }
        if let s = h.snowfall[safe: i] ?? nil, s > 0 { reasons.append("nieve") }

        if reasons.isEmpty { close(); continue }
        if var c = current, c.end == t {
            c.end = hourEnd
            for r in reasons where !c.reasons.contains(r) { c.reasons.append(r) }
            current = c
        } else {
            close()
            current = (t, hourEnd, reasons)
        }
    }
    close()
    return windows
}

/// Human report: one line per window, e.g. "🕒 16:00–19:00 — tormenta, ráfagas".
public func report(_ windows: [RiskWindow], timeZone: TimeZone = .current) -> String {
    guard !windows.isEmpty else {
        return "El pronóstico horario no marca horas de riesgo en las próximas 24 h, pero la alerta sigue vigente."
    }
    let hm = DateFormatter()
    hm.dateFormat = "EEE HH:mm"
    hm.locale = Locale(identifier: "es_AR")
    hm.timeZone = timeZone
    return "Horarios con más cuidado:\n" + windows.map {
        "🕒 \(hm.string(from: $0.start))–\(hm.string(from: $0.end).suffix(5)) — \($0.reasons.joined(separator: ", "))"
    }.joined(separator: "\n")
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
