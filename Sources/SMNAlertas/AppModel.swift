import AppKit
import Combine
import SMNCore

/// Single source of truth for the panel, Settings and the menu bar icon.
@MainActor
final class AppModel: ObservableObject {
    /// The SMN feed is cached 1–3 min by Cloudflare; 5 min is plenty and fits the download budget.
    static let pollInterval: Duration = .seconds(5 * 60)

    let monitor = AlertMonitor()
    let notifier = AlertNotifier()
    @Published private(set) var city: City? = Preferences.city
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
    @Published private(set) var demo: (alerts: [CAPAlert], hours: [HourPoint])?
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

    var alerts: [CAPAlert] {
        #if DEV_TOOLS
        if let demo { return demo.alerts }
        #endif
        return monitor.active
    }

    /// Next 24 h of the hourly forecast (only fetched while an alert is active).
    var hours: [HourPoint] {
        #if DEV_TOOLS
        if let demo { return demo.hours }
        #endif
        let now = Date()
        return monitor.forecast?.points(from: now, to: now.addingTimeInterval(24 * 3600)) ?? []
    }

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
        if city == nil { onOpenSettings() }
    }

    func refresh() async {
        notifier.refreshAuthorizationStatus()        // the user may toggle it in System Settings at any time
        guard !isDemo, let city else { return }
        let fresh = await monitor.check(at: city.coordinate)
        announce(fresh, report: reportText())
    }

    func setCity(_ city: City) async {
        Preferences.city = city
        self.city = city
        await refresh()
    }

    func openNotificationSettings() { notifier.openNotificationSettings() }

    // MARK: - Alerting

    private func announce(_ fresh: [CAPAlert], report: String) {
        for alert in fresh { notifier.post(alert, body: report.isEmpty ? alert.displayDescription : report) }
        guard let worst = fresh.first else { return }       // sorted worst first
        onAlarm(worst.level, Preferences.alarmPolicy.reaction(to: worst.level, at: Date()))
    }

    private func reportText() -> String {
        guard let forecast = monitor.forecast else { return "" }
        let now = Date()
        return report(riskWindows(forecast, from: now, to: now.addingTimeInterval(24 * 3600)))
    }

    // MARK: - Demo states (development builds only)

    #if DEV_TOOLS
    /// `announce: false` only changes what the UI shows (used by --snapshots).
    func runDemo(_ state: DemoState, announce: Bool = true) {
        let now = Date()
        let alerts = state.alerts(now: now)
        demo = (alerts, alerts.isEmpty ? [] : state.hours(now: now))
        if announce, let alert = mostSevere(alerts) {
            notifier.post(alert, body: "(Prueba) " + alert.displayDescription)
            onAlarm(alert.level, Preferences.alarmPolicy.reaction(to: alert.level, at: now))
        }
    }

    func endDemo() {
        demo = nil
        Task { await refresh() }
    }
    #endif
}
