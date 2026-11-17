import Foundation
import Testing
@testable import SMNCore

@Suite("Current weather")
struct CurrentWeatherTests {
    @Test func decodesOpenMeteoResponse() throws {
        let json = #"{"current":{"time":"2026-11-17T03:00","temperature_2m":18.6,"weather_code":2,"is_day":0},"daily":{"time":["2026-11-17"],"temperature_2m_max":[29.4],"temperature_2m_min":[14.1]}}"#
        let w = try JSONDecoder().decode(CurrentWeather.self, from: Data(json.utf8))
        #expect(w == CurrentWeather(temperature: 18.6, weatherCode: 2, isDay: false, todayMax: 29.4, todayMin: 14.1))
        #expect(w.temperatureText == "19°")
        #expect(w.summary == "Parcialmente nublado")
        #expect(w.symbolName == "cloud.moon.fill")
    }

    @Test func negativeTemperaturesRoundSensibly() {
        #expect(CurrentWeather(temperature: -0.4, weatherCode: 71, isDay: true, todayMax: nil, todayMin: nil).temperatureText == "0°")
        #expect(CurrentWeather(temperature: -2.6, weatherCode: 71, isDay: true, todayMax: nil, todayMin: nil).temperatureText == "-3°")
    }

    @Test func everyCodeHasAWordAndASymbol() {
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            let w = CurrentWeather(temperature: 20, weatherCode: code, isDay: true, todayMax: nil, todayMin: nil)
            #expect(w.summary != "—", "code \(code)")
            #expect(w.symbolName != "thermometer.medium", "code \(code)")
        }
    }
}
