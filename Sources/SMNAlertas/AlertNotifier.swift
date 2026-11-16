import AppKit
import UserNotifications
import SMNCore

/// System notifications and the per-level alert sound.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called when the user clicks a notification.
    var onOpen: () -> Void = {}
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// False when the user turned notifications off for the app: the UI must say so, or alerts fail silently.
    private(set) var notificationsAllowed = true
    var onAuthorizationChange: () -> Void = {}

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
            let allowed = [.authorized, .provisional].contains(settings.authorizationStatus)
            Task { @MainActor in
                guard let self, self.notificationsAllowed != allowed else { return }
                self.notificationsAllowed = allowed
                self.onAuthorizationChange()
            }
        }
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=local.smnalertas")!)
    }

    func post(_ alert: CAPAlert, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.level.emoji) \(alert.levelLabel): \(alert.event.capitalized)"
        content.subtitle = validity(of: alert)
        content.body = body
        content.sound = nil        // the app plays its own per-level sound; avoid a double chime
        center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil))
    }

    /// Yellow: one soft ping. Orange: one louder chime. Red: three chimes.
    func playSound(for level: AlertLevel) {
        guard Preferences.soundEnabled else { return }
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
        await MainActor.run { onOpen() }
    }
}

/// "Vigente hasta lun 16 18:00".
func validity(of alert: CAPAlert) -> String {
    guard let expires = alert.expires else { return "Vigente" }
    let f = DateFormatter()
    f.dateFormat = "EEE d HH:mm"
    f.locale = Locale(identifier: "es_AR")
    return "Vigente hasta \(f.string(from: expires))"
}
