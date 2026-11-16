import AppKit
import UserNotifications
import os
import SMNCore

let feedURL = URL(string: "https://ssl.smn.gob.ar/CAP/AR.php")!
let pollInterval: TimeInterval = 5 * 60   // feed is cached ~1-3 min by Cloudflare; 5 min is plenty
let log = Logger(subsystem: "local.smnalertas", category: "app")
let maxDownloadsPerPoll = 80              // 80 per 5 min + feed stays under SMN's 180 per 10 min

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    var cache: [URL: CAPAlert?] = [:]          // CAP files are immutable per URL
    var active: [CAPAlert] = []
    var reportText = ""
    var lastCheck: Date?
    var lastError: String?
    var pending = 0
    var timer: Timer?
    var blinkTimer: Timer?

    var city: (name: String, lat: Double, lon: Double)? {
        guard let name = defaults.string(forKey: "cityName") else { return nil }
        return (name, defaults.double(forKey: "lat"), defaults.double(forKey: "lon"))
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        rebuildMenu()
        if city == nil { askCity() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            Task { @MainActor in await self.check() }
        }
        Task { await check() }
        // The timer stalls during sleep: check on wake, after giving Wi-Fi a moment to reconnect.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                await self.check()
            }
        }
    }

    // Show banners even though the app is technically "active" as a menu bar agent.
    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        Task { @MainActor in self.status.button?.performClick(nil) }
        done()
    }

    // MARK: - Polling

    func check() async {
        guard !demo else { return }   // a demo state stays on screen until "Volver a los datos reales"
        guard let city else { rebuildMenu(); return }
        do {
            let html = String(decoding: try await fetch(feedURL), as: UTF8.self)
            let links = capLinks(inFeedHTML: html)
            guard !links.isEmpty else { throw URLError(.cannotParseResponse) }

            // CAP files never change per URL, so keep them on disk across restarts.
            for url in links where cache[url] == nil {
                if let data = try? Data(contentsOf: diskFile(url)) { cache[url] = .some(CAPParser.parse(data, url: url)) }
            }
            // SMN allows 180 XML requests / 10 min: download a batch per poll,
            // short-term notices first, then the region where the user's alerts usually come from.
            let region = defaults.string(forKey: "region")
            func priority(_ u: URL) -> Int { u.path.contains("avisocortoplazo") ? 0 : capRegion(u) == region ? 1 : 2 }
            let missing = links.filter { cache[$0] == nil }.sorted { priority($0) < priority($1) }
            await withTaskGroup(of: (URL, CAPAlert??).self) { group in
                for url in missing.prefix(maxDownloadsPerPoll) {
                    group.addTask {
                        guard let data = try? await self.fetch(url) else { return (url, nil) }  // retry next poll
                        try? data.write(to: self.diskFile(url))
                        return (url, .some(CAPParser.parse(data, url: url)))
                    }
                }
                for await (url, result) in group { if let result { cache[url] = .some(result) } }
            }
            cache = cache.filter { links.contains($0.key) }
            pending = links.filter { cache[$0] == nil }.count
            pruneDisk(keeping: links)

            let now = Date()
            var byID: [String: CAPAlert] = [:]
            for case let a?? in links.map({ cache[$0] }) where a.isActive(at: now) && a.contains(lat: city.lat, lon: city.lon) {
                byID[a.identifier] = a
            }
            active = byID.values.sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
            if let r = active.compactMap({ $0.url.flatMap(capRegion) }).first { defaults.set(r, forKey: "region") }

            if !active.isEmpty {
                let forecast = try JSONDecoder().decode(HourlyForecast.self,
                                                        from: try await fetch(HourlyForecast.url(lat: city.lat, lon: city.lon)))
                reportText = report(riskWindows(forecast, from: now, to: now.addingTimeInterval(24 * 3600)))
            } else {
                reportText = ""
            }

            // While zones are still pending an alert may be missing, not ended: don't forget its state yet.
            let previous = defaults.dictionary(forKey: "notifiedLevels") as? [String: Int] ?? [:]
            var (toNotify, state) = alertsToNotify(active: active, previous: previous)
            if pending > 0 { state.merge(previous) { now, _ in now } }
            toNotify.forEach(notify)
            if let worst = toNotify.first { blink(level: worst.level) }   // sorted worst first
            defaults.set(state, forKey: "notifiedLevels")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        lastCheck = Date()
        rebuildMenu()
    }

    nonisolated static let capDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SMNAlertas/cap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated func diskFile(_ url: URL) -> URL {
        Self.capDir.appendingPathComponent(url.pathComponents.suffix(2).joined(separator: "__"))
    }

    func pruneDisk(keeping links: [URL]) {
        let keep = Set(links.map { diskFile($0).lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.capDir, includingPropertiesForKeys: nil)) ?? []
        for f in files where !keep.contains(f.lastPathComponent) { try? FileManager.default.removeItem(at: f) }
    }

    nonisolated func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("SMNAlertas/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func notify(_ a: CAPAlert) {
        let c = UNMutableNotificationContent()
        c.title = "\(a.emoji) Alerta \(a.level): \(a.event.capitalized)"
        c.subtitle = until(a)
        c.body = reportText.isEmpty ? a.description : reportText
        c.sound = nil   // the app plays its own per-level sound (playSound), avoid a double chime
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: a.identifier, content: c, trigger: nil))
    }

    func until(_ a: CAPAlert) -> String {
        guard let e = a.expires else { return "Vigente" }
        let f = DateFormatter()
        f.dateFormat = "EEE d HH:mm"
        f.locale = Locale(identifier: "es_AR")
        return "Vigente hasta \(f.string(from: e))"
    }

    // MARK: - Menu

    func updateIcon(dotVisible: Bool = true) {
        let icon = menuBarIcon(for: active)
        status.button?.image = menuBarImage(symbol: icon.symbol, level: icon.level, dotVisible: dotVisible)
    }

    /// Yellow: one soft ping. Orange: one louder chime. Red: three chimes.
    func playSound(level: String) {
        guard !defaults.bool(forKey: "soundOff") else { return }
        log.notice("sound \(level, privacy: .public)")
        let (name, times) = level == "rojo" ? ("Sosumi", 3) : level == "naranja" ? ("Hero", 1) : ("Ping", 1)
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.9) { NSSound(named: name)?.play() }
        }
    }

    /// Blink the level dot and repeat the sound every 4 s until the menu is opened.
    /// Sound stops after 2 min so an empty room doesn't chime forever; the dot keeps blinking.
    func blink(level: String) {
        blinkTimer?.invalidate()
        var ticks = 0
        log.notice("blink start \(level, privacy: .public)")
        playSound(level: level)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                ticks += 1
                self.updateIcon(dotVisible: ticks % 2 == 0)
                if ticks % 8 == 0 && ticks <= 240 { self.playSound(level: level) }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        log.notice("menu opened, blink stopped")
        blinkTimer?.invalidate()
        updateIcon()
    }

    func rebuildMenu() {
        if blinkTimer?.isValid != true { updateIcon() }

        let menu = NSMenu()
        menu.delegate = self
        if let city {
            menu.addItem(disabled("📍 \(city.name)"))
        } else {
            menu.addItem(disabled("Configurá tu ciudad para recibir alertas"))
        }
        menu.addItem(.separator())

        if active.isEmpty {
            menu.addItem(disabled(city == nil ? "—" : "🟢 Sin alertas para tu zona"))
        } else {
            for a in active {
                let item = NSMenuItem(title: "\(a.emoji) \(a.headline.isEmpty ? a.event : a.headline)",
                                      action: #selector(openSMN), keyEquivalent: "")
                item.target = self
                item.toolTip = [a.description, a.instruction].filter { !$0.isEmpty }.joined(separator: "\n\n")
                menu.addItem(item)
                menu.addItem(disabled("     \(until(a))"))
            }
            menu.addItem(.separator())
            for line in reportText.split(separator: "\n") { menu.addItem(disabled(String(line))) }
            if active.contains(where: \.mentionsHail) { menu.addItem(disabled("🧊 Posible granizo")) }
        }

        menu.addItem(.separator())
        if let lastError { menu.addItem(disabled("⚠️ Error al consultar: \(lastError)")) }
        if pending > 0 { menu.addItem(disabled("⏳ Faltan revisar \(pending) zonas (límite del SMN)")) }
        if let lastCheck {
            menu.addItem(disabled("Última consulta: \(lastCheck.formatted(date: .omitted, time: .shortened))"))
        }
        menu.addItem(action("Actualizar ahora", #selector(refresh), "r"))
        menu.addItem(action("Cambiar ciudad…", #selector(changeCity), ","))
        let sound = action("Sonido al llegar una alerta", #selector(toggleSound), "")
        sound.state = defaults.bool(forKey: "soundOff") ? .off : .on
        menu.addItem(sound)
        let demoItem = NSMenuItem(title: "Probar estados", action: nil, keyEquivalent: "")
        let demoMenu = NSMenu()
        for (i, d) in demoStates.enumerated() {
            let item = action(d.title, #selector(runDemo(_:)), "")
            item.tag = i
            demoMenu.addItem(item)
        }
        if demo {
            demoMenu.addItem(.separator())
            demoMenu.addItem(action("Volver a los datos reales", #selector(endDemo), ""))
        }
        demoItem.submenu = demoMenu
        menu.addItem(demoItem)
        menu.addItem(action("Abrir smn.gob.ar/alertas", #selector(openSMN), ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
    }

    func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    func action(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc func refresh() { Task { await check() } }
    @objc func toggleSound() {
        defaults.set(!defaults.bool(forKey: "soundOff"), forKey: "soundOff")
        rebuildMenu()
        if !defaults.bool(forKey: "soundOff") { playSound(level: "amarillo") }   // preview on enable
    }
    @objc func openSMN() { NSWorkspace.shared.open(URL(string: "https://www.smn.gob.ar/alertas")!) }
    @objc func changeCity() { askCity() }

    // MARK: - Demo states

    var demo = false
    let demoStates: [(title: String, event: String, headline: String, severity: String, shortTerm: Bool, description: String)] = [
        ("Sin alertas", "", "", "", false, ""),
        ("🟡 Alerta amarilla por tormentas", "Tormentas", "Tormentas", "Moderate", false,
         "Tormentas aisladas, algunas fuertes, con ocasional caída de granizo."),
        ("🟡 Alerta amarilla por nevadas", "Nevadas", "Nevadas", "Moderate", false, "Nevadas de variada intensidad."),
        ("🟠 Alerta naranja por lluvias", "Lluvias", "Lluvias", "Severe", false, "Lluvias intensas, acumulados de 70 a 100 mm."),
        ("🟠 Alerta naranja por viento zonda", "Viento Zonda", "Viento Zonda", "Severe", false, "Ráfagas de hasta 90 km/h."),
        ("🔴 Alerta roja por tormentas", "Tormentas", "Tormentas", "Extreme", false, "Tormentas severas con lluvias intensas."),
        ("⚠️ Aviso naranja a corto plazo (granizo)", "TORMENTAS FUERTES",
         "AVISO NARANJA POR TORMENTAS FUERTES CON CAIDA DE GRANIZO", "Severe", true, "Tormentas fuertes con caída de granizo."),
    ]

    @objc func runDemo(_ sender: NSMenuItem) {
        let d = demoStates[sender.tag]
        demo = true
        blinkTimer?.invalidate()
        if d.event.isEmpty {
            active = []
            reportText = ""
        } else {
            var a = CAPAlert()
            a.identifier = "demo-\(UUID().uuidString)"
            a.event = d.event
            a.headline = d.headline
            a.severity = d.severity
            a.description = d.description
            a.expires = Date().addingTimeInterval(3 * 3600)
            a.url = URL(string: "https://ssl.smn.gob.ar/feeds/CAP/" + (d.shortTerm ? "avisocortoplazo/demo.xml" : "xml_generados/demo.xml"))
            active = [a]
            let f = DateFormatter()
            f.dateFormat = "EEE HH:00"
            f.locale = Locale(identifier: "es_AR")
            let start = Date().addingTimeInterval(3600), end = start.addingTimeInterval(2 * 3600)
            reportText = "(Prueba) Horarios con más cuidado:\n🕒 \(f.string(from: start))–\(f.string(from: end).suffix(5)) — \(d.event.lowercased())"
            notify(a)
        }
        rebuildMenu()
        if let a = active.first { blink(level: a.level) }
    }

    @objc func endDemo() {
        demo = false
        blinkTimer?.invalidate()
        Task { await check() }
    }

    // MARK: - City

    func askCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "¿En qué ciudad estás?"
        alert.informativeText = "Se usa para saber si una alerta del SMN cubre tu zona."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Ej: Río Cuarto"
        field.stringValue = city?.name ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task { await geocode(query) }
    }

    struct GeoResults: Decodable {
        struct R: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String? }
        let results: [R]?
    }

    func geocode(_ query: String) async {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "1"),
                            .init(name: "language", value: "es"), .init(name: "countryCode", value: "AR")]
        guard let data = try? await fetch(comps.url!),
              let r = (try? JSONDecoder().decode(GeoResults.self, from: data))?.results?.first else {
            let a = NSAlert()
            a.messageText = "No encontré \"\(query)\" en Argentina."
            a.runModal()
            return askCity()
        }
        defaults.set([r.name, r.admin1].compactMap { $0 }.joined(separator: ", "), forKey: "cityName")
        defaults.set(r.latitude, forKey: "lat")
        defaults.set(r.longitude, forKey: "lon")
        await check()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
