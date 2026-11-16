import Combine
import Foundation
import os

private let log = Logger(subsystem: "local.smnalertas", category: "monitor")

/// Polls the SMN CAP feed and tracks which alerts cover a location.
/// Network, disk and clock are injected so the whole flow can be tested without the real SMN.
@MainActor
public final class AlertMonitor: ObservableObject {
    public static let feedURL = URL(string: "https://ssl.smn.gob.ar/CAP/AR.php")!

    @Published public private(set) var active: [CAPAlert] = []
    @Published public private(set) var forecast: HourlyForecast?
    @Published public private(set) var pendingZones = 0
    @Published public private(set) var lastCheck: Date?
    @Published public private(set) var lastError: String?

    private let http: HTTPClient
    private let store: CAPStore
    private let defaults: UserDefaults
    private let maxDownloads: Int
    private let now: @Sendable () -> Date
    private var cache: [URL: CAPAlert?] = [:]      // .some(nil): downloaded, but not a usable alert
    private var isChecking = false

    private enum Key {
        static let notified = "notifiedLevels"     // [event key: AlertLevel.rawValue]
        static let region = "region"
    }

    /// `maxDownloadsPerCheck`: SMN allows 180 XML requests per 10 min; 80 per 5-min check plus the feed stays under it.
    public init(http: HTTPClient = URLSessionHTTPClient(), store: CAPStore = DiskCAPStore.standard,
                defaults: UserDefaults = .standard, maxDownloadsPerCheck: Int = 80,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.store = store
        self.defaults = defaults
        self.maxDownloads = maxDownloadsPerCheck
        self.now = now
    }

    /// Refreshes `active` for `location` and returns the alerts that deserve a new notification.
    @discardableResult
    public func check(at location: Coordinate) async -> [CAPAlert] {
        guard !isChecking else { return [] }       // wake, timer and manual refresh can overlap
        isChecking = true
        defer { isChecking = false; lastCheck = now() }
        do {
            let links = capLinks(in: String(decoding: try await http.data(from: Self.feedURL), as: UTF8.self))
            guard !links.isEmpty else { throw FetchError.emptyFeed }
            await loadAlerts(links)

            let current = now()
            var seen = Set<String>()
            active = links.compactMap { cache[$0] ?? nil }
                .filter { $0.isActive(at: current) && $0.contains(location) && seen.insert($0.identifier).inserted }
                .sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
            if let region = active.lazy.compactMap({ $0.url.flatMap(capRegion) }).first {
                defaults.set(region, forKey: Key.region)
            }
            // The forecast only enriches the report: a failure must never hold back an SMN alert.
            forecast = active.isEmpty ? nil
                : try? JSONDecoder().decode(HourlyForecast.self, from: await http.data(from: HourlyForecast.url(for: location)))
            lastError = nil
            let notify = updateNotificationState()
            log.notice("check: \(links.count) zones, \(self.pendingZones) pending, \(self.active.count) active, \(notify.count) new")
            return notify
        } catch {
            lastError = error.localizedDescription
            log.error("check failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Loads CAP files from disk, then downloads a limited batch: short-term notices first,
    /// then the region the user's alerts usually come from.
    private func loadAlerts(_ links: [URL]) async {
        for url in links where cache[url] == nil {
            if let data = store.load(url) { cache[url] = .some(CAPParser.parse(data, url: url)) }
        }
        let region = defaults.string(forKey: Key.region)
        func priority(_ u: URL) -> Int { u.path.contains("avisocortoplazo") ? 0 : capRegion(u) == region ? 1 : 2 }
        let missing = links.filter { cache[$0] == nil }.sorted { priority($0) < priority($1) }.prefix(maxDownloads)

        let http = self.http
        await withTaskGroup(of: (URL, Data?).self) { group in
            for url in missing {
                group.addTask { (url, try? await http.data(from: url)) }
            }
            for await (url, data) in group {
                guard let data else { continue }       // failed (e.g. 429): retried on the next check
                store.save(data, for: url)
                cache[url] = .some(CAPParser.parse(data, url: url))
            }
        }
        let current = Set(links)
        cache = cache.filter { current.contains($0.key) }
        store.prune(keeping: links)
        pendingZones = links.filter { cache[$0] == nil }.count
    }

    private func updateNotificationState() -> [CAPAlert] {
        let saved = defaults.dictionary(forKey: Key.notified) as? [String: Int] ?? [:]
        let previous = saved.compactMapValues(AlertLevel.init(rawValue:))
        var (notify, state) = alertsToNotify(active: active, previous: previous)
        // While zones are still pending, a missing alert may just not be downloaded yet: keep its state.
        if pendingZones > 0 { state.merge(previous) { current, _ in current } }
        defaults.set(state.mapValues(\.rawValue), forKey: Key.notified)
        return notify
    }
}
