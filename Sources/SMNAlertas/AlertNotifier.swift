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

    func post(_ alert: CAPAlert, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.level.emoji) \(alert.levelLabel): \(alert.displayEvent)"
        content.subtitle = validity(of: alert)
        content.body = body
        content.categoryIdentifier = Self.category
        content.sound = nil        // the app plays its own per-level sound; avoid a double chime
        center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil))
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
