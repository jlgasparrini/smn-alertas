import AppKit
import UserNotifications
import SMNCore

let feedURL = URL(string: "https://ssl.smn.gob.ar/CAP/AR.php")!
let pollInterval: TimeInterval = 5 * 60   // feed is cached ~1-3 min by Cloudflare; 5 min is plenty
let maxDownloadsPerPoll = 80              // 80 per 5 min + feed stays under SMN's 180 per 10 min

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    var cache: [URL: CAPAlert?] = [:]          // CAP files are immutable per URL
    var active: [CAPAlert] = []
    var reportText = ""
    var lastCheck: Date?
    var lastError: String?
    var pending = 0
    var timer: Timer?

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
        guard let city else { rebuildMenu(); return }
        do {
            let html = String(decoding: try await fetch(feedURL), as: UTF8.self)
            let links = capLinks(inFeedHTML: html)
            guard !links.isEmpty else { throw URLError(.cannotParseResponse) }

            // SMN allows 180 XML requests / 10 min: download a batch per poll, short-term notices first.
            let missing = links.filter { cache[$0] == nil }
                .sorted { $0.path.contains("avisocortoplazo") && !$1.path.contains("avisocortoplazo") }
            await withTaskGroup(of: (URL, CAPAlert??).self) { group in
                for url in missing.prefix(maxDownloadsPerPoll) {
                    group.addTask {
                        guard let data = try? await self.fetch(url) else { return (url, nil) }  // retry next poll
                        return (url, .some(CAPParser.parse(data, url: url)))
                    }
                }
                for await (url, result) in group { if let result { cache[url] = .some(result) } }
            }
            cache = cache.filter { links.contains($0.key) }
            pending = links.filter { cache[$0] == nil }.count

            let now = Date()
            var byID: [String: CAPAlert] = [:]
            for case let a?? in links.map({ cache[$0] }) where a.isActive(at: now) && a.contains(lat: city.lat, lon: city.lon) {
                byID[a.identifier] = a
            }
            active = byID.values.sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }

            if !active.isEmpty {
                let forecast = try JSONDecoder().decode(HourlyForecast.self,
                                                        from: try await fetch(HourlyForecast.url(lat: city.lat, lon: city.lon)))
                reportText = report(riskWindows(forecast, from: now, to: now.addingTimeInterval(24 * 3600)))
            } else {
                reportText = ""
            }

            var notified = Set(defaults.stringArray(forKey: "notified") ?? [])
            for a in active where !notified.contains(a.identifier) {
                notify(a)
                notified.insert(a.identifier)
            }
            defaults.set(Array(notified.suffix(1000)), forKey: "notified")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        lastCheck = Date()
        rebuildMenu()
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
        c.sound = a.level == "amarillo" ? .default : .defaultCritical
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

    func rebuildMenu() {
        let worst = active.map(\.level)
        let symbol = worst.isEmpty ? "cloud.sun" : "exclamationmark.triangle.fill"
        status.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Alertas SMN")
        status.button?.contentTintColor = worst.contains("rojo") ? .systemRed
            : worst.contains("naranja") ? .systemOrange : worst.isEmpty ? nil : .systemYellow

        let menu = NSMenu()
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
        }

        menu.addItem(.separator())
        if let lastError { menu.addItem(disabled("⚠️ Error al consultar: \(lastError)")) }
        if pending > 0 { menu.addItem(disabled("⏳ Faltan revisar \(pending) zonas (límite del SMN)")) }
        if let lastCheck {
            menu.addItem(disabled("Última consulta: \(lastCheck.formatted(date: .omitted, time: .shortened))"))
        }
        menu.addItem(action("Actualizar ahora", #selector(refresh), "r"))
        menu.addItem(action("Cambiar ciudad…", #selector(changeCity), ","))
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
    @objc func openSMN() { NSWorkspace.shared.open(URL(string: "https://www.smn.gob.ar/alertas")!) }
    @objc func changeCity() { askCity() }

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
