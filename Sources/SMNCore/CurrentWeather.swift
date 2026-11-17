import Foundation

/// Weather right now plus today's range, from Open-Meteo. Fetched on every check for every city
/// (unlike the hourly forecast, which is only fetched while an alert is in force).
public struct CurrentWeather: Decodable, Equatable, Sendable {
    public let temperature: Double        // °C
    public let weatherCode: Int
    public let isDay: Bool
    public let todayMax: Double?
    public let todayMin: Double?

    public init(temperature: Double, weatherCode: Int, isDay: Bool, todayMax: Double?, todayMin: Double?) {
        self.temperature = temperature
        self.weatherCode = weatherCode
        self.isDay = isDay
        self.todayMax = todayMax
        self.todayMin = todayMin
    }

    public static func url(for c: Coordinate) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.lat)&longitude=\(c.lon)"
            + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=1")!
    }

    private struct Raw: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double?]; let temperature_2m_min: [Double?] }
        let current: Current
        let daily: Daily?
    }

    public init(from decoder: Decoder) throws {
        let raw = try Raw(from: decoder)
        self.init(temperature: raw.current.temperature_2m, weatherCode: raw.current.weather_code,
                  isDay: raw.current.is_day == 1,
                  todayMax: raw.daily?.temperature_2m_max.first ?? nil, todayMin: raw.daily?.temperature_2m_min.first ?? nil)
    }

    /// "24°" (rounded, no unit letter, like the menu bar clock style).
    public var temperatureText: String { "\(Int(temperature.rounded()))°" }

    /// WMO weather code in plain Argentine Spanish.
    public var summary: String {
        switch weatherCode {
        case 0: isDay ? "Despejado" : "Noche despejada"
        case 1, 2: "Parcialmente nublado"
        case 3: "Nublado"
        case 45, 48: "Niebla"
        case 51...57: "Llovizna"
        case 61, 80: "Lluvia débil"
        case 63, 81: "Lluvia"
        case 65, 82: "Lluvia fuerte"
        case 66, 67: "Lluvia helada"
        case 71...77, 85, 86: "Nieve"
        case 95...99: "Tormenta"
        default: "—"
        }
    }

    /// SF Symbol matching `summary`, with day and night variants where they exist.
    public var symbolName: String {
        switch weatherCode {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 80, 81, 66, 67: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }
}
