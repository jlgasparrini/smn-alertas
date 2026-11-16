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
        let first = await m.check(at: riocuarto)
        #expect(first.map(\.id) == ["id-0"])
        #expect(m.active.map(\.id) == ["id-0"])
        #expect(m.lastError == nil)

        let second = await m.check(at: riocuarto)
        #expect(second.isEmpty)
        #expect(m.active.count == 1)
    }

    @Test func forecastFailureDoesNotBlockTheAlert() async {
        _ = await publish(1)                            // FakeHTTP fails Open-Meteo with 503
        let m = monitor()
        #expect(await m.check(at: riocuarto).count == 1)
        #expect(m.forecast == nil)
        #expect(m.lastError == nil)
    }

    @Test func respectsDownloadBudgetAndPrioritisesShortTermNotices() async throws {
        var urls = await publish(5)
        let notice = capURL("acp", shortTerm: true)
        await http.set(notice, capXML(id: "acp", event: "TORMENTAS FUERTES", severity: "Severe"))
        urls.append(notice)
        await http.set(AlertMonitor.feedURL, rss(urls))

        let m = monitor(maxDownloads: 2)
        let fresh = await m.check(at: riocuarto)
        let capRequests = await http.requests.filter { $0.path.contains("/feeds/CAP/") }
        #expect(capRequests.count == 2)
        #expect(capRequests.contains(notice))
        #expect(m.pendingZones == 4)
        #expect(fresh.map(\.id).contains("acp"))
    }

    @Test func failedDownloadsAreRetriedNotCached() async {
        let urls = await publish(1)
        await http.fail(urls[0])
        let m = monitor()
        #expect(await m.check(at: riocuarto).isEmpty)
        #expect(m.pendingZones == 1)

        await http.heal(urls[0])
        #expect(await m.check(at: riocuarto).count == 1)
        #expect(m.pendingZones == 0)
    }

    @Test func keepsNotificationStateWhileZonesArePending() async {
        _ = await publish(1)
        #expect(await monitor().check(at: riocuarto).count == 1)

        // Restart while SMN rate-limits: our zone isn't loaded yet, so it must not count as "ended".
        let urls = (0..<3).map { capURL("\($0)") }
        await http.set(AlertMonitor.feedURL, rss(urls))
        for url in urls { await http.fail(url) }
        let restarted = AlertMonitor(http: http, store: MemoryStore(), defaults: defaults)
        #expect(await restarted.check(at: riocuarto).isEmpty)

        for url in urls { await http.heal(url) }
        await http.set(urls[0], capXML(id: "id-0-update"))           // same event, new identifier
        await http.set(urls[1], capXML(id: "x", around: Coordinate(lat: -50, lon: -70)))
        await http.set(urls[2], capXML(id: "y", around: Coordinate(lat: -50, lon: -70)))
        #expect(await restarted.check(at: riocuarto).isEmpty)        // no duplicate notification
    }

    @Test func reusesStoredFilesAcrossLaunches() async {
        _ = await publish(4)
        await monitor().check(at: riocuarto)
        #expect(store.count == 4)

        await http.clearLog()
        let relaunched = monitor()
        await relaunched.check(at: riocuarto)
        let capRequests = await http.requests.filter { $0.path.contains("/feeds/CAP/") }
        #expect(capRequests.isEmpty)
        #expect(relaunched.active.count == 1)
    }

    @Test func ignoresExpiredAlerts() async {
        let url = capURL("old")
        await http.set(url, capXML(id: "old", expires: "2020-01-01T00:00:00-03:00"))
        await http.set(AlertMonitor.feedURL, rss([url]))
        let m = monitor()
        #expect(await m.check(at: riocuarto).isEmpty)
        #expect(m.active.isEmpty)
    }

    @Test func downloadsTheUsersRegionFirstOnceLearned() async {
        let mine = capURL("mine", region: "Patagonia")
        await http.set(mine, capXML(id: "mine"))
        await http.set(AlertMonitor.feedURL, rss([mine]))
        await monitor().check(at: riocuarto)                  // learns "Patagonia"

        // New batch: two other-region zones listed before ours, budget of one download.
        let others = [capURL("a", region: "Llanura"), capURL("b", region: "Cordillera")]
        let next = capURL("mine2", region: "Patagonia")
        for u in others { await http.set(u, capXML(id: u.lastPathComponent, around: Coordinate(lat: -50, lon: -70))) }
        await http.set(next, capXML(id: "mine2", severity: "Severe"))
        await http.set(AlertMonitor.feedURL, rss(others + [next]))
        await http.clearLog()
        let fresh = await AlertMonitor(http: http, store: MemoryStore(), defaults: defaults, maxDownloadsPerCheck: 1)
            .check(at: riocuarto)
        #expect(await http.requests.contains(next))
        #expect(fresh.map(\.id) == ["mine2"])
    }

    @Test func reportsFeedErrors() async {
        await http.fail(AlertMonitor.feedURL)
        let m = monitor()
        #expect(await m.check(at: riocuarto).isEmpty)
        #expect(m.lastError == FetchError.status(429).errorDescription)
        #expect(m.lastCheck != nil)
    }
}

@Suite("Geocoder")
struct GeocoderTests {
    @Test func buildsCityNameWithProvince() async throws {
        let http = FakeHTTP()
        let json = #"{"results":[{"name":"Río Cuarto","latitude":-33.13,"longitude":-64.35,"admin1":"Córdoba"}]}"#
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: "rio cuarto"), .init(name: "count", value: "1"),
                            .init(name: "language", value: "es"), .init(name: "countryCode", value: "AR")]
        await http.set(comps.url!, Data(json.utf8))
        let city = try #require(try await Geocoder(http: http).search("rio cuarto").first)
        #expect(city.name == "Río Cuarto, Córdoba")
        #expect(city.coordinate == Coordinate(lat: -33.13, lon: -64.35))
    }
}
