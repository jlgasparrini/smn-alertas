/// SMN warning colours, ordered by severity.
public enum AlertLevel: Int, Comparable, CaseIterable, Sendable {
    case yellow = 1, orange, red

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Adjective agreeing with the noun: "Alerta amarilla" but "Aviso amarillo".
    public func name(feminine: Bool = true) -> String {
        switch self {
        case .yellow: feminine ? "amarilla" : "amarillo"
        case .orange: "naranja"
        case .red: feminine ? "roja" : "rojo"
        }
    }

    public var emoji: String {
        switch self {
        case .yellow: "🟡"
        case .orange: "🟠"
        case .red: "🔴"
        }
    }

    /// From a CAP `<severity>`; the headline wins when it names a colour ("AVISO NARANJA POR…").
    public init(severity: String, headline: String = "") {
        let h = headline.uppercased()
        if h.contains("ROJ") { self = .red }
        else if h.contains("NARANJA") { self = .orange }
        else if h.contains("AMARILL") { self = .yellow }
        else {
            switch severity {
            case "Extreme": self = .red
            case "Severe": self = .orange
            default: self = .yellow
            }
        }
    }
}
