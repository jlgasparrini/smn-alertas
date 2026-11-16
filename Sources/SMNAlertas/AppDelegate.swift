import AppKit
import os
import SMNCore

let log = Logger(subsystem: "local.smnalertas", category: "app")

/// Wires the monitor, notifications and menu bar together and runs the polling loop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The SMN feed is cached 1–3 min by Cloudflare; 5 min is plenty and fits the download budget.
    static let pollInterval: Duration = .seconds(5 * 60)

    private let monitor = AlertMonitor()
    private let notifier = AlertNotifier()
    private lazy var statusItem = StatusItemController(
        actions: .init(
            refresh: { [unowned self] in Task { await refresh() } },
            changeCity: { [unowned self] in askCity() },
            toggleSound: { [unowned self] in toggleSound() },
            runDemo: { [unowned self] in runDemo($0) },
            endDemo: { [unowned self] in endDemo() },
            openNotificationSettings: { [unowned self] in notifier.openNotificationSettings() }),
        playSound: { [unowned self] in notifier.playSound(for: $0) })
    private var pollTask: Task<Void, Never>?
    private var demo: (alerts: [CAPAlert], report: String)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestAuthorization()
        notifier.onOpen = { [unowned self] in statusItem.openMenu() }
        notifier.onAuthorizationChange = { [unowned self] in render() }
        render()
        if Preferences.city == nil { askCity() }

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
    }

    func refresh() async {
        notifier.refreshAuthorizationStatus()       // the user may toggle it in System Settings at any time
        guard demo == nil, let city = Preferences.city else { return render() }
        let fresh = await monitor.check(at: city.coordinate)
        let report = currentReport()
        for alert in fresh { notifier.post(alert, body: report.isEmpty ? alert.description : report) }
        if let worst = fresh.first { statusItem.startAlarm(worst.level) }   // sorted worst first
        render()
    }

    private func currentReport() -> String {
        guard let forecast = monitor.forecast else { return "" }
        let now = Date()
        return report(riskWindows(forecast, from: now, to: now.addingTimeInterval(24 * 3600)))
    }

    private func render() {
        statusItem.render(.init(
            city: Preferences.city,
            alerts: demo?.alerts ?? monitor.active,
            report: demo?.report ?? currentReport(),
            pendingZones: monitor.pendingZones,
            lastCheck: monitor.lastCheck,
            lastError: monitor.lastError,
            soundEnabled: Preferences.soundEnabled,
            demoActive: demo != nil,
            notificationsAllowed: notifier.notificationsAllowed))
    }

    private func toggleSound() {
        Preferences.soundEnabled.toggle()
        render()
        if Preferences.soundEnabled { notifier.playSound(for: .yellow) }    // preview
    }

    // MARK: - Demo states (polling pauses until "Volver a los datos reales")

    private func runDemo(_ state: DemoState) {
        statusItem.stopAlarm()
        let alerts = state.alert().map { [$0] } ?? []
        demo = (alerts, alerts.isEmpty ? "" : state.report())
        if let alert = alerts.first {
            notifier.post(alert, body: state.report())
            statusItem.startAlarm(alert.level)
        }
        render()
    }

    private func endDemo() {
        demo = nil
        statusItem.stopAlarm()
        Task { await refresh() }
    }

    // MARK: - City

    private func askCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "¿En qué ciudad estás?"
        alert.informativeText = "Se usa para saber si una alerta del SMN cubre tu zona."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Ej: Río Cuarto"
        field.stringValue = Preferences.city?.name ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task { await setCity(query) }
    }

    private func setCity(_ query: String) async {
        guard let city = try? await Geocoder().search(query).first else {
            let alert = NSAlert()
            alert.messageText = "No encontré \"\(query)\" en Argentina."
            alert.runModal()
            return askCity()
        }
        Preferences.city = city
        await refresh()
    }
}
