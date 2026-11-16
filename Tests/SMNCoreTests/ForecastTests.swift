import Foundation
import Testing
@testable import SMNCore

@Suite("Risk windows")
struct ForecastTests {
    let forecast = try! JSONDecoder().decode(HourlyForecast.self, from: Data("""
    {"utc_offset_seconds":-10800,"hourly":{
     "time":["2026-11-16T14:00","2026-11-16T15:00","2026-11-16T16:00","2026-11-16T17:00","2026-11-16T18:00","2026-11-16T19:00"],
     "precipitation":[0,5,0.5,0,3,null],"precipitation_probability":[0,90,80,0,70,null],
     "wind_gusts_10m":[10,20,60,10,10,null],"weather_code":[1,95,3,1,61,null],"snowfall":[0,0,0,0,0,null]}}
    """.utf8))
    let from = ISO8601DateFormatter().date(from: "2026-11-16T14:30:00-03:00")!

    @Test func groupsConsecutiveRiskyHoursAndMergesReasons() throws {
        let w = riskWindows(forecast, from: from, to: from.addingTimeInterval(24 * 3600))
        try #require(w.count == 2)
        #expect(w[0].reasons == ["tormenta", "lluvia fuerte", "ráfagas"])
        #expect(w[0].end.timeIntervalSince(w[0].start) == 2 * 3600)      // 15:00–17:00
        #expect(w[1].reasons == ["lluvia fuerte"])
    }

    @Test func reportListsWindowsInLocalTime() {
        let text = report(riskWindows(forecast, from: from, to: from.addingTimeInterval(24 * 3600)),
                          timeZone: TimeZone(secondsFromGMT: -10800)!)
        #expect(text.contains("15:00–17:00"))
        #expect(text.contains("18:00–19:00"))
    }

    @Test func pointsCoverTheWindowAndDefaultMissingValuesToZero() {
        let points = forecast.points(from: from, to: from.addingTimeInterval(24 * 3600))
        #expect(points.count == 6)                                    // 14:00 overlaps 14:30, so it's included
        #expect(points[1].risks == ["tormenta", "lluvia fuerte"])
        #expect(points[2].risks == ["ráfagas"])
        #expect(points[5].precipitation == 0 && points[5].risks.isEmpty)   // all-null hour
    }

    @Test func emptyReportStillSaysTheAlertIsOn() {
        #expect(report([]).contains("la alerta sigue vigente"))
    }
}
