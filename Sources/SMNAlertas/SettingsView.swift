import AppKit
import ServiceManagement
import SMNCore
import SwiftUI

/// Settings window: location search, alert behaviour and login item.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Preferences.Key.soundEnabled) private var soundEnabled = true
    @AppStorage(Preferences.Key.repeatUntilSeen) private var repeatUntilSeen = true
    @AppStorage(Preferences.Key.quietYellowAtNight) private var quietYellowAtNight = false

    @State private var query = ""
    @State private var results: [City] = []
    @State private var searchFailed = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?

    var body: some View {
        Form {
            Section("Ubicación") {
                LabeledContent("Ciudad", value: model.city?.name ?? "Sin elegir")
                TextField("Buscar", text: $query, prompt: Text("Escribí tu ciudad, por ejemplo Río Cuarto"))
                    .textFieldStyle(.roundedBorder)
                ForEach(results) { city in
                    Button { choose(city) } label: {
                        HStack {
                            Text(city.name)
                            Spacer()
                            if city == model.city { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if searchFailed {
                    Text("No encontré esa ciudad en Argentina.").foregroundStyle(.secondary)
                }
            }
            .task(id: query) { await search() }

            Section("Avisos") {
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

            Section("General") {
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
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: "es_AR"))
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
        Task { await model.setCity(city) }
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

/// Hosts SettingsView in a regular window (the app has no SwiftUI App scene).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = "Ajustes de SMN Alertas"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
