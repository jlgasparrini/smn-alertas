import AppKit
import UserNotifications
import SMNCore

/// System notifications and the per-level alert sound.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called when the user clicks a notification or its "Ver detalles" button.
    var onOpen: () -> Void = {}
    /// Called from the "Silenciar" button: stop blinking and sound without opening the panel.
    var onSilence: () -> Void = {}
    /// Called when macOS permission changes; `false` means alerts would fail silently, so the UI must say so.
    var onAuthorizationChange: (Bool) -> Void = { _ in }
    private var allowed: Bool?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.category,
            actions: [UNNotificationAction(identifier: Self.details, title: "Ver detalles", options: [.foreground]),
                      UNNotificationAction(identifier: Self.silence, title: "Silenciar")],
            intentIdentifiers: [])])
    }

    private nonisolated static let category = "alert", details = "details", silence = "silence"

    // Callbacks are @Sendable: the system calls them on a background queue, and a main-actor
    // closure would trap at runtime in Swift 6.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable [weak self] granted, error in
            log.notice("notifications granted=\(granted) error=\(String(describing: error), privacy: .public)")
            Task { @MainActor in self?.refreshAuthorizationStatus() }
        }
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { @Sendable [weak self] settings in
            let status = settings.authorizationStatus
            let allowed = [.authorized, .provisional].contains(status)
            // The request's own error can disagree with System Settings; this status is what delivery uses.
            log.notice("notification status=\(allowed ? "allowed" : "blocked", privacy: .public) raw=\(status.rawValue)")
            Task { @MainActor in
                guard let self, self.allowed != allowed else { return }
                self.allowed = allowed
                self.onAuthorizationChange(allowed)
            }
        }
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=local.smnalertas")!)
    }

    /// `city` is named only when the user follows more than one.
    func post(_ alert: CAPAlert, city: String?, body: String) {
        send(id: alert.identifier, title: "\(alert.level.emoji) \(alert.levelLabel): \(alert.displayEvent)",
             subtitle: [city, validity(of: alert)].compactMap { $0 }.joined(separator: " · "), body: body)
    }

    /// "🟠 Tormentas: pasa a naranja a las 02:10".
    func postEscalation(event: String, to level: AlertLevel, at date: Date, city: String?) {
        let minutes = max(1, Int(date.timeIntervalSinceNow / 60))
        send(id: "escalation-\(event)-\(level.rawValue)-\(Int(date.timeIntervalSince1970))",
             title: "\(level.emoji) \(event): pasa a \(level.name(feminine: true)) a las \(formatted(date, "HH:mm"))",
             subtitle: city ?? "", body: "Faltan \(minutes) min. Prepará lo que necesites antes.")
    }

    func postEnded(event: String, city: String?) {
        send(id: "ended-\(event)-\(Date().timeIntervalSince1970)", title: "✅ \(event): terminó la alerta",
             subtitle: city ?? "", body: "El SMN ya no tiene alertas vigentes por este fenómeno en tu zona.", actions: false)
    }

    private func send(id: String, title: String, subtitle: String, body: String, actions: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        if actions { content.categoryIdentifier = Self.category }      // "Silenciar" means nothing for good news
        content.sound = nil        // the app plays its own per-level sound; avoid a double chime
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Yellow: one soft ping. Orange: one louder chime. Red: three chimes.
    func playSound(for level: AlertLevel) {
        log.notice("sound \(level.name(), privacy: .public)")
        let (name, times) = switch level {
        case .red: ("Sosumi", 3)
        case .orange: ("Hero", 1)
        case .yellow: ("Ping", 1)
        }
        Task {
            for i in 0..<times {
                if i > 0 { try? await Task.sleep(for: .milliseconds(900)) }
                NSSound(named: name)?.play()
            }
        }
    }

    // Show banners even though a menu bar agent counts as the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let silence = response.actionIdentifier == Self.silence
        await MainActor.run { silence ? onSilence() : onOpen() }
    }
}

/// "Vigente hasta lun 16 18:00".
func validity(of alert: CAPAlert) -> String {
    guard let expires = alert.expires else { return "Vigente" }
    return "Vigente hasta \(formatted(expires, "EEE d HH:mm"))"
}

/// Date in Argentine Spanish with a fixed pattern, e.g. "EEE d HH:mm" -> "lun 16 18:00".
func formatted(_ date: Date, _ pattern: String) -> String {
    let f = DateFormatter()
    f.dateFormat = pattern
    f.locale = Locale(identifier: "es_AR")
    return f.string(from: date)
}
