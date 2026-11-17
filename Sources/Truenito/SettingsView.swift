import AppKit
import ServiceManagement
import SMNCore
import SwiftUI

/// One tab of the Settings window. Tabs keep every page short enough for a laptop screen.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case cities, alerts, general, about

        var title: String {
            switch self {
            case .cities: "Ciudades"
            case .alerts: "Avisos"
            case .general: "General"
            case .about: "Acerca de"
            }
        }

        var symbol: String {
            switch self {
            case .cities: "mappin.and.ellipse"
            case .alerts: "bell.badge"
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    let tab: Tab
    @EnvironmentObject private var model: AppModel
    @AppStorage(Preferences.Key.soundEnabled) private var soundEnabled = true
    @AppStorage(Preferences.Key.repeatUntilSeen) private var repeatUntilSeen = true
    @AppStorage(Preferences.Key.quietYellowAtNight) private var quietYellowAtNight = false
    @AppStorage(Preferences.Key.appearance) private var appearance = "system"
    @AppStorage(Preferences.Key.minimumLevel) private var minimumLevel = AlertLevel.yellow.rawValue

    @State private var query = ""
    @State private var results: [City] = []
    @State private var searchFailed = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?
    @State private var autoUpdate = true

    var body: some View {
        Form {
            switch tab {
            case .cities: cities
            case .alerts: alerts
            case .general: general
            case .about: about
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: "es_AR"))
    }

    @ViewBuilder private var cities: some View {
        Section {
            ForEach(model.cities) { city in
                HStack {
                    Label(city.name, systemImage: "mappin")
                    Spacer()
                    Button { model.removeCity(city) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Quitar \(city.name)")
                        .accessibilityLabel("Quitar \(city.name)")
                }
            }
            TextField(model.cities.isEmpty ? "Ciudad" : "Agregar", text: $query,
                      prompt: Text("Buscá una ciudad, por ejemplo Río Cuarto"))
            ForEach(results) { city in
                let added = model.cities.contains { $0.name == city.name }
                Button { choose(city) } label: {
                    HStack {
                        Text(city.name)
                        Spacer()
                        Image(systemName: added ? "checkmark" : "plus.circle").foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(added)
            }
            if searchFailed {
                Text("No encontré esa ciudad en Argentina.").foregroundStyle(.secondary)
            }

        } footer: {
            if model.cities.count > 1 {
                Text("Te avisa por cualquiera de ellas y te dice cuál.")
            }
        }
        .task(id: query) { await search() }
    }

    @ViewBuilder private var alerts: some View {
        Section {
            Picker(selection: $minimumLevel) {
                ForEach(AlertLevel.allCases, id: \.rawValue) { level in
                    Text(level == .yellow ? "Todas las alertas" : "Desde \(level.name())").tag(level.rawValue)
                }
            } label: {
                Text("Avisarme")
                Text("Las de menor nivel se ven en el panel, pero no notifican ni suenan.")
            }
            Toggle("Sonido al llegar una alerta", isOn: $soundEnabled)
                .onChange(of: soundEnabled) { on in if on { model.notifier.playSound(for: .yellow) } }
            Toggle("Repetir el sonido hasta que abras el panel", isOn: $repeatUntilSeen)
                .disabled(!soundEnabled)
            Toggle(isOn: $quietYellowAtNight) {
                Text("Silenciar alertas amarillas de noche")
                Text("De 23 a 7 h solo parpadean. Las naranjas y rojas suenan siempre.")
            }
            .disabled(!soundEnabled)
        }
    }

    @ViewBuilder private var general: some View {
        Section {
            Picker("Apariencia", selection: $appearance) {
                Text("Como el sistema").tag("system")
                Text("Clara").tag("light")
                Text("Oscura").tag("dark")
            }
            .onChange(of: appearance) { _ in Preferences.applyAppearance() }
            Toggle("Mostrar la temperatura en la barra de menú", isOn: $model.showTemperature)
            Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
            if let loginNote {
                Text(loginNote).font(.callout).foregroundStyle(.secondary)
            }
            LabeledContent("Notificaciones de macOS") {
                if model.notificationsAllowed {
                    Label("Activadas", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Activar…") { model.openNotificationSettings() }
                }
            }
        }

        if let updater = model.updater {
            Section("Actualizaciones") {
                Toggle(isOn: Binding(get: { autoUpdate }, set: { autoUpdate = $0; updater.automaticallyChecksForUpdates = $0 })) {
                    Text("Buscar actualizaciones automáticamente")
                    Text("Una vez por día. Antes de instalar te pregunta.")
                }
                LabeledContent("Versión \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    Button("Buscar ahora") { model.checkForUpdates() }
                }
            }
            .onAppear { autoUpdate = updater.automaticallyChecksForUpdates }
        }
    }

    @ViewBuilder private var about: some View {
        // Open-Meteo's data license (CC BY 4.0) asks for attribution.
        Section {
            LabeledContent("Alertas") { Link("Servicio Meteorológico Nacional", destination: URL(string: "https://www.smn.gob.ar")!) }
            LabeledContent("Clima y búsqueda") { Link("Open-Meteo (CC BY 4.0)", destination: URL(string: "https://open-meteo.com")!) }
            LabeledContent("Código abierto") { Link("GitHub", destination: URL(string: "https://github.com/jlgasparrini/truenito")!) }
        } footer: {
            Text("App no oficial, hecha por un particular. No está asociada al SMN.")
        }
    }

    /// Debounced: `.task(id:)` cancels the previous search when the query changes.
    private func search() async {
        searchFailed = false
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let found = (try? await Geocoder().search(q, limit: 5)) ?? []
        guard !Task.isCancelled else { return }
        results = found
        searchFailed = found.isEmpty
    }

    private func choose(_ city: City) {
        query = ""
        results = []
        Task { await model.addCity(city) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = SMAppService.mainApp.status == .requiresApproval
                ? "Aprobalo en Configuración del Sistema → General → Ítems de inicio." : nil
        } catch {
            loginNote = "No se pudo cambiar: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Settings in a regular window with toolbar tabs, like the system apps (there's no SwiftUI App scene).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let tabs = SettingsTabs()
            tabs.tabStyle = .toolbar
            for tab in SettingsView.Tab.allCases {
                let host = NSHostingController(rootView: SettingsView(tab: tab).environmentObject(model))
                host.sizingOptions = .preferredContentSize
                host.title = tab.title
                let item = NSTabViewItem(viewController: host)
                item.label = tab.title
                item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
                tabs.addTabViewItem(item)
            }
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            window = w
            tabs.fitWindow(animate: false)
            w.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Resizes the window to the selected tab, keeping its top edge in place, as System Settings-style panes do.
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        fitWindow(animate: true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        if viewController == selectedController { fitWindow(animate: true) }
    }

    private var selectedController: NSViewController? {
        tabViewItems.indices.contains(selectedTabViewItemIndex) ? tabViewItems[selectedTabViewItemIndex].viewController : nil
    }

    func fitWindow(animate: Bool) {
        guard let window = view.window, let selected = selectedController else { return }
        let size = selected.view.fittingSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}
