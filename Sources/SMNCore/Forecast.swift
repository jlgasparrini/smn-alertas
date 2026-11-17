import Foundation

/// Hourly forecast from Open-Meteo (free, no key), turned into `HourPoint`s once when decoded.
public struct HourlyForecast: Decodable, Sendable {
    public let hours: [HourPoint]

    public static func url(for c: Coordinate) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.lat)&longitude=\(c.lon)"
            + "&hourly=precipitation,wind_gusts_10m,weather_code,snowfall"
            + "&timezone=auto&forecast_days=3")!
    }

    private struct Raw: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let precipitation: [Double?]
            let wind_gusts_10m: [Double?]
            let weather_code: [Int?]
            let snowfall: [Double?]
        }
        let hourly: Hourly
        let utc_offset_seconds: Int
    }

    /// Missing values count as zero.
    public init(from decoder: Decoder) throws {
        let raw = try Raw(from: decoder)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: raw.utc_offset_seconds)
        let h = raw.hourly
        hours = h.time.indices.compactMap { i in
            guard let t = fmt.date(from: h.time[i]) else { return nil }
            return HourPoint(date: t,
                             precipitation: (h.precipitation[safe: i] ?? nil) ?? 0,
                             gust: (h.wind_gusts_10m[safe: i] ?? nil) ?? 0,
                             weatherCode: h.weather_code[safe: i] ?? nil,
                             snowfall: (h.snowfall[safe: i] ?? nil) ?? 0)
        }
    }
}

public struct RiskWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date          // exclusive: start of the hour after the last risky one
    public let reasons: [String]
}

/// Thresholds for "be careful" hours. Rough, conservative values.
let thunderCodes = 95...99        // WMO weather codes for thunderstorms
let heavyRainMM = 2.0
let strongGustKMH = 50.0

/// One forecast hour, ready for charts and risk checks.
public struct HourPoint: Identifiable, Equatable, Sendable {
    public let date: Date
    public let precipitation: Double      // mm
    public let gust: Double               // km/h
    public let weatherCode: Int?
    public let snowfall: Double           // cm
    public var id: Date { date }

    public init(date: Date, precipitation: Double, gust: Double, weatherCode: Int?, snowfall: Double) {
        self.date = date
        self.precipitation = precipitation
        self.gust = gust
        self.weatherCode = weatherCode
        self.snowfall = snowfall
    }

    /// Why this hour deserves care; empty when it doesn't.
    public var risks: [String] {
        var r: [String] = []
        if let c = weatherCode, thunderCodes.contains(c) { r.append("tormenta") }
        if precipitation >= heavyRainMM { r.append("lluvia fuerte") }
        if gust >= strongGustKMH { r.append("ráfagas") }
        if snowfall > 0 { r.append("nieve") }
        return r
    }
}

extension HourlyForecast {
    /// Hours overlapping `from..<to`.
    public func points(from: Date, to: Date) -> [HourPoint] {
        hours.filter { $0.date.addingTimeInterval(3600) > from && $0.date < to }
    }
}

/// Groups consecutive risky hours between `from` and `to` into windows.
public func riskWindows(_ f: HourlyForecast, from: Date, to: Date) -> [RiskWindow] {
    riskWindows(f.points(from: from, to: to))
}

/// Groups consecutive risky hours into windows.
public func riskWindows(_ points: [HourPoint]) -> [RiskWindow] {
    var windows: [RiskWindow] = []
    var current: (start: Date, end: Date, reasons: [String])?

    func close() {
        if let c = current { windows.append(RiskWindow(start: c.start, end: c.end, reasons: c.reasons)) }
        current = nil
    }

    for p in points {
        let reasons = p.risks
        let hourEnd = p.date.addingTimeInterval(3600)
        if reasons.isEmpty { close(); continue }
        if var c = current, c.end == p.date {
            c.end = hourEnd
            for r in reasons where !c.reasons.contains(r) { c.reasons.append(r) }
            current = c
        } else {
            close()
            current = (p.date, hourEnd, reasons)
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
