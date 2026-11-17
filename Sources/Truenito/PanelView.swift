import Charts
import SMNCore
import SwiftUI

/// Content of the popover that opens from the menu bar icon.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var contentHeight: CGFloat = 0

    private var places: [PlaceStatus] { model.places }
    private var several: Bool { places.count > 1 }
    private var alertCount: Int { places.map { groupAlerts($0.alerts).count }.reduce(0, +) }

    private static let gutter: CGFloat = 14       // same as the panel padding

    /// The popover must never run off the screen: the middle section scrolls past this height.
    private var maxContentHeight: CGFloat {
        min(520, (NSScreen.main?.visibleFrame.height ?? 800) - 180)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // The scroll area reaches into the panel's right margin, so the scrollbar sits there
            // instead of over the cards.
            ScrollView {
                content
                    .padding(.trailing, Self.gutter)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            }
            .frame(height: min(contentHeight, maxContentHeight))
            .padding(.trailing, -Self.gutter)
            .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .environment(\.locale, Locale(identifier: "es_AR"))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.notificationsAllowed { notificationsOff }
            if model.cities.isEmpty {
                noCity
            } else {
                ForEach(places.filter { !$0.alerts.isEmpty }) { place in
                    let groups = groupAlerts(place.alerts)
                    if several {
                        HStack {
                            Text(place.city.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            if let current = place.current { CompactWeather(current: current) }
                        }
                        .padding(.top, 4)
                    }
                    ForEach(groups) { AlertRow(group: $0) }
                    if !place.hours.isEmpty {
                        ForecastCard(hours: place.hours, level: groups.map(\.worst.level).max() ?? .yellow)
                    }
                }
                let calmPlaces = places.filter(\.alerts.isEmpty)
                if alertCount == 0 || !calmPlaces.isEmpty { calm(calmPlaces) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                // A pin, not the GPS arrow: the cities are chosen by hand.
                Label(several ? "Truenito" : model.cities.first?.name ?? "Truenito",
                      systemImage: several ? "mappin.and.ellipse" : "mappin")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                Spacer()
                headerButtons
            }
            if !several, let current = places.first?.current { WeatherNow(current: current) }
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var headerButtons: some View {
            Button { Task { await model.refresh() } } label: {
                if model.monitor.isChecking {
                    ProgressView().controlSize(.small).accessibilityLabel("Consultando al SMN")
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 20, height: 20)
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .disabled(model.monitor.isChecking)
            .help("Actualizar (⌘R)")
            .accessibilityLabel("Actualizar")
            Menu {
                Button("Ajustes…") { model.onOpenSettings() }.keyboardShortcut(",")
                if model.updater != nil { Button("Buscar actualizaciones…") { model.checkForUpdates() } }
                #if DEV_TOOLS
                Menu("Probar estados") {
                    ForEach(DemoState.all, id: \.title) { state in Button(state.title) { model.runDemo(state) } }
                    if model.isDemo {
                        Divider()
                        Button("Volver a los datos reales") { model.endDemo() }
                    }
                }
                #endif
                Divider()
                Button("Salir de Truenito") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Más opciones")
    }

    /// Nil when there's nothing to add: the calm card already says "no alerts".
    private var subtitle: String? {
        if model.isDemo { return "Estado de prueba" }
        // With one city the weather line takes this place; the cards already say how many alerts.
        guard several else { return nil }
        switch alertCount {
        case 0: return "\(places.count) ciudades"
        case 1: return "1 alerta en \(places.count) ciudades"
        default: return "\(alertCount) alertas en \(places.count) ciudades"
        }
    }

    private var notificationsOff: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            Text("Las notificaciones de macOS están desactivadas.").font(.callout)
            Spacer(minLength: 0)
            Button("Activar") { model.openNotificationSettings() }.controlSize(.small)
        }
        .card()
    }

    private var noCity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Elegí tu ciudad para saber si una alerta del SMN te afecta.").font(.callout)
            Button("Elegir ciudad…") { model.onOpenSettings() }
        }
        .card()
    }

    /// One city: a single line. Several: "Sin alertas" and each calm city with its temperature.
    private func calm(_ calmPlaces: [PlaceStatus]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(several ? "Sin alertas" : "No hay alertas del SMN para tu zona.", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
            if several {
                ForEach(calmPlaces) { place in
                    HStack {
                        Text(place.city.name)
                        Spacer()
                        if let current = place.current { CompactWeather(current: current) }
                    }
                    .padding(.leading, 26)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Link(destination: URL(string: "https://www.smn.gob.ar/alertas")!) {
                Label("smn.gob.ar", systemImage: "arrow.up.right.square").font(.caption)
            }
        }
    }

    private static let relative = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_AR")
        return f
    }()

    private var statusLine: String {
        if let error = model.monitor.lastError { return error }
        guard let last = model.monitor.lastCheck else { return "Consultando al SMN…" }
        var text = "Actualizado " + Self.relative.localizedString(for: last, relativeTo: .now)
        if model.monitor.pendingZones > 0 { text += " · faltan \(model.monitor.pendingZones) zonas" }
        return text
    }
}

/// "☁️ 24°  Parcialmente nublado · Máx 29° Mín 16°" under the city name. Clicking it opens Apple's
/// Weather app: this app covers alerts, Weather covers everything else.
private struct WeatherNow: View {
    let current: CurrentWeather
    @State private var hovering = false

    var body: some View {
        Button(action: openWeather) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: current.symbolName).symbolRenderingMode(.multicolor).font(.title3)
                Text(current.temperatureText).font(.title2.weight(.semibold)).monospacedDigit()
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                Image(systemName: "arrow.up.forward").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Abrir en Tiempo")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre la app Tiempo")
    }



    private var detail: String {
        guard let max = current.todayMax, let min = current.todayMin else { return current.summary }
        return "\(current.summary) · Máx \(Int(max.rounded()))° Mín \(Int(min.rounded()))°"
    }
}

@MainActor private func openWeather() {
    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") else { return }
    NSWorkspace.shared.openApplication(at: app, configuration: .init())
}

/// "☀️ 31°" next to a city name when there are several; also opens Weather.
private struct CompactWeather: View {
    let current: CurrentWeather

    var body: some View {
        Button(action: openWeather) {
            HStack(spacing: 4) {
                Image(systemName: current.symbolName).symbolRenderingMode(.multicolor)
                Text(current.temperatureText).monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .help("\(current.summary) · Abrir en Tiempo")
        .accessibilityLabel("\(current.temperatureText), \(current.summary)")
    }
}

/// One phenomenon: tinted with the level in force, a bar when the level changes over time,
/// description and recommendations folded under "Detalles".
private struct AlertRow: View {
    let group: AlertGroup
    @State private var showDetails = false

    private var worst: CAPAlert { group.worst }
    private var tint: Color { group.current.tint }
    private var showsBar: Bool { group.timeline.count > 1 && !group.isShortTerm }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: worst.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(group.current.onTint)
                .frame(width: 30, height: 30)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(worst.displayEvent).font(.headline)
                    Spacer()
                    if !showsBar {          // the bar's first segment already names the current level
                        LevelBadge(text: group.isShortTerm ? "Ahora" : group.current.name().capitalized, level: group.current)
                    }
                }
                if showsBar {
                    TimelineBar(steps: group.timeline).padding(.vertical, 2).accessibilityLabel(timeline)
                } else {
                    Text(timeline).font(.subheadline).foregroundStyle(Self.onCard)
                }
                if group.mentionsHail {
                    Label("Posible granizo", systemImage: "cloud.hail").font(.caption).foregroundStyle(Self.onCard)
                }
                DisclosureGroup("Detalles", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        if worst.displayDescription != worst.displayEvent {
                            Text(worst.displayDescription).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                        if !worst.instructionSteps.isEmpty {
                            Text("Qué hacer").font(.callout.weight(.semibold))
                            ForEach(worst.instructionSteps, id: \.self) { step in
                                Label(step, systemImage: "checkmark").font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .card(tint: tint)
    }

    /// Secondary text on the tinted card: grey would lose contrast against the level colour.
    static let onCard = Color.primary.opacity(0.75)

    /// Also the VoiceOver reading of the bar: "Amarilla hasta las 20:59 · luego naranja hasta el mar 02:59".
    private var timeline: String {
        if group.isShortTerm { return "Está ocurriendo · " + until(group.alerts.last?.expires) }
        let steps = group.timeline
        if steps.count == 1 { return until(steps[0].until).capitalizedFirst }       // the badge already names the level
        return steps.enumerated().map { i, step in
            let level = step.level.name()
            return (i == 0 ? level.capitalized : "luego " + level) + " " + until(step.until)
        }.joined(separator: " · ")
    }

    private func until(_ date: Date?) -> String {
        guard let date else { return "vigente" }
        return Calendar.current.isDate(date, inSameDayAs: .now) ? "hasta las \(formatted(date, "HH:mm"))"
                                                                : "hasta el \(formatted(date, "EEE HH:mm"))"
    }
}

/// Levels from now on as coloured segments sized by duration, named inside when they fit,
/// with the change times underneath.
private struct TimelineBar: View {
    let steps: [AlertGroup.Step]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let ends = steps.map { $0.until ?? now.addingTimeInterval(3600) }
            let total = max(ends.last!.timeIntervalSince(now), 60)
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (d: Date) in w * min(max(d.timeIntervalSince(now) / total, 0), 1) }
                ZStack(alignment: .topLeading) {
                    ForEach(steps.indices, id: \.self) { i in
                        let from = i == 0 ? 0 : x(ends[i - 1]) + 1
                        let to = i == steps.count - 1 ? w : x(ends[i]) - 1
                        ViewThatFits {
                            Text(steps[i].level.name().capitalized)
                            Color.clear.frame(width: 0)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(steps[i].level.onTint)
                        .frame(width: max(to - from, 4), height: 18)
                        .background(steps[i].level.tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .offset(x: from)
                    }
                    // shortcut: labels closer than ~50 pt overlap; fine for SMN slots, which last hours.
                    ForEach(ends.indices.dropLast(), id: \.self) { i in
                        Text(time(ends[i])).position(x: min(max(x(ends[i]), 24), w - 24), y: 29)
                    }
                    Text("Ahora").position(x: 16, y: 29)
                    Text(time(ends.last!)).fixedSize().frame(width: w, alignment: .trailing).position(x: w / 2, y: 29)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AlertRow.onCard)
            }
        }
        .frame(height: 36)
    }

    private func time(_ d: Date) -> String {
        formatted(d, Calendar.current.isDate(d, inSameDayAs: .now) ? "HH:mm" : "EEE HH:mm")
    }
}

private struct LevelBadge: View {
    let text: String
    let level: AlertLevel

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(level.onTint)
            .background(level.tint, in: Capsule())
    }
}

extension AlertLevel {
    var tint: Color { Color(nsColor: color) }
    /// Text and glyphs on a level-coloured fill: dark on yellow, white otherwise.
    var onTint: Color { self == .yellow ? .black : .white }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private struct ForecastCard: View {
    let hours: [HourPoint]
    /// The riskiest hours are shaded in the colour of the worst level they fall under.
    let level: AlertLevel

    private var windows: [RiskWindow] { riskWindows(hours) }
    /// A chart of near-zero rain is noise: show it only for risky hours or at least 1 mm somewhere.
    private var worthCharting: Bool { !windows.isEmpty || (hours.map(\.precipitation).max() ?? 0) >= 1 }

    var body: some View {
        if worthCharting { chart } else {
            Label("Sin horas de riesgo en el pronóstico de las próximas 24 h.", systemImage: "clock")
                .font(.callout).foregroundStyle(.secondary).card()
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Próximas 24 h").font(.headline)
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(windows, id: \.start) { w in
                    RectangleMark(xStart: .value("Desde", w.start), xEnd: .value("Hasta", w.end))
                        .foregroundStyle(level.tint.opacity(0.25))
                }
                ForEach(hours) { h in
                    BarMark(x: .value("Hora", h.date, unit: .hour), y: .value("Lluvia (mm)", h.precipitation))
                        .foregroundStyle(.blue)
                }
            }
            .chartYScale(domain: 0...max(5, hours.map(\.precipitation).max() ?? 0))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) { AxisValueLabel(formatted(date, "H") + " h") }
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 90)
            .accessibilityLabel("Lluvia por hora en las próximas 24 horas")

            // Only the swatches carry colour; the words stay readable secondary text.
            HStack(spacing: 12) {
                swatch(.blue, "Lluvia (mm)")
                swatch(level.tint.opacity(0.5), "Más cuidado")
                Spacer(minLength: 0)
                if let gust = hours.map(\.gust).max(), gust >= 40 {
                    Label("Ráfagas \(Int(gust)) km/h", systemImage: "wind").fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .card()
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }

    private var summary: String {
        guard let first = windows.first else { return "Sin horas de riesgo" }
        return "Más cuidado de \(formatted(first.start, "H")) a \(formatted(first.end, "H")) h"
    }
}

extension View {
    /// Rounded, subtly filled container used for every block in the panel; alerts pass their level colour.
    func card(tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { $0.opacity(0.13) } ?? Color.primary.opacity(0.055), in: shape)
            .overlay(shape.strokeBorder(tint?.opacity(0.35) ?? .clear, lineWidth: 1))
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
