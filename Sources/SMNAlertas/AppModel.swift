import AppKit
import Combine
import SMNCore

/// What the panel shows for one city.
struct PlaceStatus: Identifiable {
    let city: City
    let alerts: [CAPAlert]
    /// Next 24 h of the hourly forecast (only fetched while an alert is active).
    let hours: [HourPoint]
    var id: String { city.id }
}

/// Single source of truth for the panel, Settings and the menu bar icon.
@MainActor
final class AppModel: ObservableObject {
    /// The SMN feed is cached 1–3 min by Cloudflare; 5 min is plenty and fits the download budget.
    static let pollInterval: Duration = .seconds(5 * 60)

    let monitor = AlertMonitor()
    let notifier = AlertNotifier()
    @Published private(set) var cities: [City] = Preferences.cities
    @Published private(set) var notificationsAllowed = true

    /// Asks the menu bar to blink (and maybe sound) for a new alert.
    var onAlarm: (AlertLevel, AlarmPolicy.Reaction) -> Void = { _, _ in }
    /// Asks the menu bar to open the panel (notification clicked).
    var onOpenPanel: () -> Void = {}
    /// Asks the menu bar to stop blinking and sounding ("Silenciar" on the notification).
    var onSilence: () -> Void = {}
    /// Opens the Settings window.
    var onOpenSettings: () -> Void = {}

    #if DEV_TOOLS
    @Published private(set) var demo: (alerts: [CAPAlert], hours: [HourPoint], otherCity: Bool)?
    #endif

    private var pollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        monitor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        notifier.onAuthorizationChange = { [weak self] allowed in self?.notificationsAllowed = allowed }
        notifier.onOpen = { [weak self] in self?.onOpenPanel() }
        notifier.onSilence = { [weak self] in self?.onSilence() }
    }

    // MARK: - What the UI shows

    var places: [PlaceStatus] {
        #if DEV_TOOLS
        if let demo {
            let city = cities.first ?? City(name: "Río Cuarto, Córdoba", coordinate: Coordinate(lat: -33.13, lon: -64.35))
            let other = City(name: "Mendoza, Mendoza", coordinate: Coordinate(lat: -32.89, lon: -68.83))
            return [PlaceStatus(city: city, alerts: demo.alerts, hours: demo.hours)]
                + (demo.otherCity ? [PlaceStatus(city: other, alerts: [], hours: [])] : [])
        }
        #endif
        let now = Date()
        return monitor.places.map {
            PlaceStatus(city: $0.city, alerts: $0.alerts,
                        hours: $0.forecast?.points(from: now, to: now.addingTimeInterval(24 * 3600)) ?? [])
        }
    }

    /// Every alert in force, for the menu bar icon.
    var alerts: [CAPAlert] { places.flatMap(\.alerts) }

    var isDemo: Bool {
        #if DEV_TOOLS
        return demo != nil
        #else
        return false
        #endif
    }

    // MARK: - Lifecycle

    func start() {
        notifier.requestAuthorization()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        // Sleep pauses the loop: check on wake, after giving Wi-Fi a moment to reconnect.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                await self?.refresh()
            }
        }
        if cities.isEmpty { onOpenSettings() }
    }

    func refresh() async {
        notifier.refreshAuthorizationStatus()        // the user may toggle it in System Settings at any time
        guard !isDemo, !cities.isEmpty else { return }
        announce(await monitor.check(cities))
    }

    func addCity(_ city: City) async {
        guard !cities.contains(where: { $0.name == city.name }) else { return }
        cities.append(city)
        Preferences.cities = cities
        await refresh()
    }

    func removeCity(_ city: City) {
        cities.removeAll { $0 == city }
        Preferences.cities = cities
        Task { await refresh() }
    }

    func openNotificationSettings() { notifier.openNotificationSettings() }

    // MARK: - Alerting

    private func announce(_ notices: [Notice]) {
        let policy = Preferences.alarmPolicy
        let wanted = notices.filter { policy.announces($0.level) }
        let named = cities.count > 1                 // with one city there's no need to say which
        for notice in wanted {
            switch notice {
            case .new(let alert, let city):
                notifier.post(alert, city: named ? city.name : nil, body: report(for: city) ?? alert.displayDescription)
            case .escalation(let event, let level, let at, let city):
                notifier.postEscalation(event: event, to: level, at: at, city: named ? city.name : nil)
            case .ended(let event, _, let city):
                notifier.postEnded(event: event, city: named ? city.name : nil)
            }
        }
        // An alert ending is good news: no blinking or sound for it.
        guard let worst = wanted.filter({ if case .ended = $0 { false } else { true } }).map(\.level).max() else { return }
        onAlarm(worst, policy.reaction(to: worst, at: Date()))
    }

    /// "Más cuidado de 15 a 18 h…" for the city's forecast, or nil without risky hours.
    private func report(for city: City) -> String? {
        guard let forecast = monitor.places.first(where: { $0.city == city })?.forecast else { return nil }
        let now = Date()
        let text = SMNCore.report(riskWindows(forecast, from: now, to: now.addingTimeInterval(24 * 3600)))
        return text.isEmpty ? nil : text
    }

    // MARK: - Demo states (development builds only)

    #if DEV_TOOLS
    /// `announce: false` only changes what the UI shows (used by --snapshots).
    func runDemo(_ state: DemoState, announce: Bool = true) {
        let now = Date()
        let alerts = state.alerts(now: now)
        demo = (alerts, alerts.isEmpty ? [] : state.hours(now: now), state.otherCity)
        if announce, let alert = mostSevere(alerts) {
            notifier.post(alert, city: nil, body: "(Prueba) " + alert.displayDescription)
            onAlarm(alert.level, Preferences.alarmPolicy.reaction(to: alert.level, at: now))
        }
    }

    func endDemo() {
        demo = nil
        Task { await refresh() }
    }
    #endif
}
