import AppKit
import SMNCore

/// The menu bar icon, its blinking "alarm" and the drop-down menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct State {
        var city: City?
        var alerts: [CAPAlert] = []
        var report = ""
        var pendingZones = 0
        var lastCheck: Date?
        var lastError: String?
        var soundEnabled = true
        var demoActive = false
        var notificationsAllowed = true
    }

    struct Actions {
        var refresh: @MainActor () -> Void
        var changeCity: @MainActor () -> Void
        var toggleSound: @MainActor () -> Void
        var runDemo: @MainActor (DemoState) -> Void
        var endDemo: @MainActor () -> Void
        var openNotificationSettings: @MainActor () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let actions: Actions
    private let playSound: @MainActor (AlertLevel) -> Void
    private var iconAlert: CAPAlert?
    private var alarmTask: Task<Void, Never>?

    init(actions: Actions, playSound: @escaping @MainActor (AlertLevel) -> Void) {
        self.actions = actions
        self.playSound = playSound
        super.init()
    }

    func render(_ state: State) {
        iconAlert = mostSevere(state.alerts)
        if alarmTask == nil { setIcon(dotVisible: true) }
        item.menu = makeMenu(state)
    }

    func openMenu() { item.button?.performClick(nil) }

    /// Blink the level dot and repeat the sound every 4 s until the menu is opened.
    /// The sound stops after 2 min so an empty room doesn't chime forever; the dot keeps blinking.
    func startAlarm(_ level: AlertLevel) {
        stopAlarm()
        log.notice("alarm start \(level.name(), privacy: .public)")
        playSound(level)
        alarmTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                tick += 1
                setIcon(dotVisible: tick % 2 == 0)
                if tick % 8 == 0 && tick <= 240 { playSound(level) }
            }
        }
    }

    func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        setIcon(dotVisible: true)
    }

    func menuWillOpen(_ menu: NSMenu) { stopAlarm() }

    private func setIcon(dotVisible: Bool) {
        item.button?.image = menuBarImage(for: iconAlert, dotVisible: dotVisible)
    }

    // MARK: - Menu

    private func makeMenu(_ s: State) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        if !s.notificationsAllowed {
            menu.addItem(ClosureMenuItem("⚠️ Las notificaciones están desactivadas — Activar…", actions.openNotificationSettings))
            menu.addItem(.separator())
        }
        menu.addItem(.label(s.city.map { "📍 \($0.name)" } ?? "Configurá tu ciudad para recibir alertas"))
        menu.addItem(.separator())

        if s.alerts.isEmpty {
            menu.addItem(.label(s.city == nil ? "—" : "🟢 Sin alertas para tu zona"))
        } else {
            for a in s.alerts {
                let row = ClosureMenuItem("\(a.level.emoji) \(a.title)") { openSMN() }
                row.toolTip = [a.description, a.instruction].filter { !$0.isEmpty }.joined(separator: "\n\n")
                menu.addItem(row)
                menu.addItem(.label("     \(validity(of: a))"))
            }
            menu.addItem(.separator())
            for line in s.report.split(separator: "\n") { menu.addItem(.label(String(line))) }
            if s.alerts.contains(where: \.mentionsHail) { menu.addItem(.label("🧊 Posible granizo")) }
        }

        menu.addItem(.separator())
        if let error = s.lastError { menu.addItem(.label("⚠️ \(error)")) }
        if s.pendingZones > 0 { menu.addItem(.label("⏳ Faltan revisar \(s.pendingZones) zonas (límite del SMN)")) }
        if let last = s.lastCheck { menu.addItem(.label("Última consulta: \(last.formatted(date: .omitted, time: .shortened))")) }
        menu.addItem(ClosureMenuItem("Actualizar ahora", key: "r", actions.refresh))
        menu.addItem(ClosureMenuItem("Cambiar ciudad…", key: ",", actions.changeCity))
        let sound = ClosureMenuItem("Sonido al llegar una alerta", actions.toggleSound)
        sound.state = s.soundEnabled ? .on : .off
        menu.addItem(sound)

        let demo = NSMenu()
        for state in DemoState.all {
            demo.addItem(ClosureMenuItem(state.title) { [actions] in actions.runDemo(state) })
        }
        if s.demoActive {
            demo.addItem(.separator())
            demo.addItem(ClosureMenuItem("Volver a los datos reales", actions.endDemo))
        }
        let demoItem = NSMenuItem(title: "Probar estados", action: nil, keyEquivalent: "")
        demoItem.submenu = demo
        menu.addItem(demoItem)
        menu.addItem(ClosureMenuItem("Abrir smn.gob.ar/alertas") { openSMN() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}

func openSMN() { NSWorkspace.shared.open(URL(string: "https://www.smn.gob.ar/alertas")!) }

/// NSMenuItem that runs a closure, so menus don't need @objc selectors on a shared target.
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", _ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @MainActor @objc private func fire() { handler() }      // AppKit fires menu actions on the main thread
}

extension NSMenuItem {
    /// A non-interactive line of text.
    static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
