import Foundation
import Testing
@testable import SMNCore

@Suite("AlertMonitor") @MainActor
struct AlertMonitorTests {
    let http = FakeHTTP()
    let store = MemoryStore()
    let defaults = freshDefaults()

    func monitor(maxDownloads: Int = 80) -> AlertMonitor {
        AlertMonitor(http: http, store: store, defaults: defaults, maxDownloadsPerCheck: maxDownloads)
    }

    /// Feed with `count` zones; zone 0 covers Río Cuarto, the rest are far away.
    func publish(_ count: Int, event: String = "Tormentas", severity: String = "Moderate") async -> [URL] {
        let urls = (0..<count).map { capURL("\($0)") }
        for (i, url) in urls.enumerated() {
            await http.set(url, capXML(id: "id-\(i)", event: event, severity: severity,
                                       around: i == 0 ? riocuarto : Coordinate(lat: -50, lon: -70)))
        }
        await http.set(AlertMonitor.feedURL, rss(urls))
        return urls
    }

    @Test func findsAlertForLocationAndNotifiesOnce() async {
        _ = await publish(3)
        let m = monitor()
        let first = await m.check([rc])
        #expect(first.compactMap(\.alert?.id) == ["id-0"])
        #expect(m.alerts.map(\.id) == ["id-0"])
        #expect(m.lastError == nil)

        let second = await m.check([rc])
        #expect(second.isEmpty)
        #expect(m.alerts.count == 1)
    }

    @Test func forecastFailureDoesNotBlockTheAlert() async {
        _ = await publish(1)                            // FakeHTTP fails Open-Meteo with 503
        let m = monitor()
        #expect(await m.check([rc]).count == 1)
        #expect(m.places.first?.forecast == nil)
        #expect(m.lastError == nil)
    }

    @Test func respectsDownloadBudgetAndPrioritisesShortTermNotices() async throws {
        var urls = await publish(5)
        let notice = capURL("acp", shortTerm: true)
        await http.set(notice, capXML(id: "acp", event: "TORMENTAS FUERTES", severity: "Severe"))
        urls.append(notice)
        await http.set(AlertMonitor.feedURL, rss(urls))

        let m = monitor(maxDownloads: 2)
        let fresh = await m.check([rc])
        let capRequests = await http.requests.filter { $0.path.contains("/feeds/CAP/") }
        #expect(capRequests.count == 2)
        #expect(capRequests.contains(notice))
        #expect(m.pendingZones == 4)
        #expect(fresh.compactMap(\.alert?.id).contains("acp"))
    }

    @Test func failedDownloadsAreRetriedNotCached() async {
        let urls = await publish(1)
        await http.fail(urls[0])
        let m = monitor()
        #expect(await m.check([rc]).isEmpty)
        #expect(m.pendingZones == 1)

        await http.heal(urls[0])
        #expect(await m.check([rc]).count == 1)
        #expect(m.pendingZones == 0)
    }

    @Test func keepsNotificationStateWhileZonesArePending() async {
        _ = await publish(1)
        #expect(await monitor().check([rc]).count == 1)

        // Restart while SMN rate-limits: our zone isn't loaded yet, so it must not count as "ended".
        let urls = (0..<3).map { capURL("\($0)") }
        await http.set(AlertMonitor.feedURL, rss(urls))
        for url in urls { await http.fail(url) }
        let restarted = AlertMonitor(http: http, store: MemoryStore(), defaults: defaults)
        #expect(await restarted.check([rc]).isEmpty)

        for url in urls { await http.heal(url) }
        await http.set(urls[0], capXML(id: "id-0-update"))           // same event, new identifier
        await http.set(urls[1], capXML(id: "x", around: Coordinate(lat: -50, lon: -70)))
        await http.set(urls[2], capXML(id: "y", around: Coordinate(lat: -50, lon: -70)))
        #expect(await restarted.check([rc]).isEmpty)        // no duplicate notification
    }

    @Test func reusesStoredFilesAcrossLaunches() async {
        _ = await publish(4)
        await monitor().check([rc])
        #expect(store.count == 4)

        await http.clearLog()
        let relaunched = monitor()
        await relaunched.check([rc])
        let capRequests = await http.requests.filter { $0.path.contains("/feeds/CAP/") }
        #expect(capRequests.isEmpty)
        #expect(relaunched.alerts.count == 1)
    }

    @Test func ignoresExpiredAlerts() async {
        let url = capURL("old")
        await http.set(url, capXML(id: "old", expires: "2020-01-01T00:00:00-03:00"))
        await http.set(AlertMonitor.feedURL, rss([url]))
        let m = monitor()
        #expect(await m.check([rc]).isEmpty)
        #expect(m.alerts.isEmpty)
    }

    @Test func downloadsTheUsersRegionFirstOnceLearned() async {
        let mine = capURL("mine", region: "Patagonia")
        await http.set(mine, capXML(id: "mine"))
        await http.set(AlertMonitor.feedURL, rss([mine]))
        await monitor().check([rc])                  // learns "Patagonia"

        // New batch: two other-region zones listed before ours, budget of one download.
        let others = [capURL("a", region: "Llanura"), capURL("b", region: "Cordillera")]
        let next = capURL("mine2", region: "Patagonia")
        for u in others { await http.set(u, capXML(id: u.lastPathComponent, around: Coordinate(lat: -50, lon: -70))) }
        await http.set(next, capXML(id: "mine2", severity: "Severe"))
        await http.set(AlertMonitor.feedURL, rss(others + [next]))
        await http.clearLog()
        let fresh = await AlertMonitor(http: http, store: MemoryStore(), defaults: defaults, maxDownloadsPerCheck: 1)
            .check([rc])
        #expect(await http.requests.contains(next))
        #expect(fresh.compactMap(\.alert?.id) == ["mine2"])
    }

    @Test func reportsFeedErrors() async {
        await http.fail(AlertMonitor.feedURL)
        let m = monitor()
        #expect(await m.check([rc]).isEmpty)
        #expect(m.lastError == FetchError.status(429).errorDescription)
        #expect(m.lastCheck != nil)
    }
}

@Suite("Geocoder")
struct GeocoderTests {
    @Test func buildsCityNameWithProvince() async throws {
        let http = FakeHTTP()
        let json = #"{"results":[{"name":"Río Cuarto","latitude":-33.13,"longitude":-64.35,"admin1":"Córdoba","feature_code":"PPLA2"},"#
            + #"{"name":"Rio Cuarto","latitude":-33.16,"longitude":-64.33,"admin1":"Córdoba","feature_code":"AIRF"},"#
            + #"{"name":"Río Cuarto","latitude":-33.2,"longitude":-64.3,"admin1":"Córdoba","feature_code":"PPL"}]}"#
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: "rio cuarto"), .init(name: "count", value: "15"),
                            .init(name: "language", value: "es"), .init(name: "countryCode", value: "AR")]
        await http.set(comps.url!, Data(json.utf8))
        let cities = try await Geocoder(http: http).search("rio cuarto", limit: 5)
        #expect(cities.count == 1)        // the airfield and the repeated name are dropped
        let city = try #require(cities.first)
        #expect(city.name == "Río Cuarto, Córdoba")
        #expect(city.coordinate == Coordinate(lat: -33.13, lon: -64.35))
    }
}

@Suite("AlertMonitor, several cities") @MainActor
struct MultiCityMonitorTests {
    let http = FakeHTTP()
    let defaults = freshDefaults()
    let far = City(name: "Ushuaia, Tierra del Fuego", coordinate: Coordinate(lat: -50, lon: -70))

    @Test func splitsAlertsPerCityAndReportsTheEnd() async {
        let urls = [capURL("0"), capURL("1")]
        await http.set(urls[0], capXML(id: "rc"))
        await http.set(urls[1], capXML(id: "far", event: "Viento", around: far.coordinate))
        await http.set(AlertMonitor.feedURL, rss(urls))
        let m = AlertMonitor(http: http, store: MemoryStore(), defaults: defaults)

        let first = await m.check([rc, far])
        #expect(m.places.map { $0.alerts.map(\.id) } == [["rc"], ["far"]])
        #expect(Set(first.compactMap(\.alert?.id)) == ["rc", "far"])

        await http.set(AlertMonitor.feedURL, rss([urls[1]]))       // Río Cuarto's alert is over
        #expect(await m.check([rc, far]) == [.ended(event: "Tormentas", level: .yellow, city: rc)])
    }

    @Test func upgradeFromOneCityDoesNotRepeatOrEndAlerts() async {
        defaults.set(["TORMENTAS": AlertLevel.yellow.rawValue], forKey: "notifiedLevels")    // 1.x state
        await http.set(capURL("0"), capXML(id: "rc"))
        await http.set(AlertMonitor.feedURL, rss([capURL("0")]))
        #expect(await AlertMonitor(http: http, store: MemoryStore(), defaults: defaults).check([rc]).isEmpty)
    }
}

@Suite("AlertMonitor, current weather") @MainActor
struct CurrentWeatherMonitorTests {
    @Test func fetchesWeatherForCalmCitiesAndKeepsItOnAFailedRefresh() async {
        let http = FakeHTTP()
        await http.set(capURL("far"), capXML(id: "far", around: Coordinate(lat: -50, lon: -70)))
        await http.set(AlertMonitor.feedURL, rss([capURL("far")]))
        let json = #"{"current":{"temperature_2m":21.2,"weather_code":0,"is_day":1},"daily":{"temperature_2m_max":[27],"temperature_2m_min":[12]}}"#
        await http.set(CurrentWeather.url(for: riocuarto), Data(json.utf8))
        let m = AlertMonitor(http: http, store: MemoryStore(), defaults: freshDefaults())
        await m.check([rc])
        #expect(m.places.first?.current?.temperatureText == "21°")
        #expect(m.places.first?.forecast == nil)         // hourly forecast only while an alert is in force

        await http.fail(CurrentWeather.url(for: riocuarto))
        await m.check([rc])
        #expect(m.places.first?.current?.temperatureText == "21°")
    }
}
