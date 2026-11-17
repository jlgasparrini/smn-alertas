import AppKit
import SMNCore

/// User settings. The toggles are read with @AppStorage in Settings using these same keys.
@MainActor
enum Preferences {
    enum Key {
        static let soundEnabled = "soundEnabled"
        static let repeatUntilSeen = "repeatUntilSeen"
        static let quietYellowAtNight = "quietYellowAtNight"
        static let minimumLevel = "minimumLevel"
        static let cities = "cities"
        static let appearance = "appearance"      // "system", "light" or "dark"
        static let showTemperature = "showTemperature"
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        // 1.0 stored the inverse ("soundOff"); carry it over once.
        if defaults.object(forKey: "soundOff") != nil {
            defaults.set(!defaults.bool(forKey: "soundOff"), forKey: Key.soundEnabled)
            defaults.removeObject(forKey: "soundOff")
        }
        defaults.register(defaults: [Key.soundEnabled: true, Key.repeatUntilSeen: true, Key.quietYellowAtNight: false,
                                      Key.minimumLevel: AlertLevel.yellow.rawValue, Key.showTemperature: true])
    }

    /// The user's cities, in the order they added them. 1.x stored a single city in separate keys.
    static var cities: [City] {
        get {
            if let data = defaults.data(forKey: Key.cities), let cities = try? JSONDecoder().decode([City].self, from: data) {
                return cities
            }
            guard let name = defaults.string(forKey: "cityName") else { return [] }
            return [City(name: name, coordinate: Coordinate(lat: defaults.double(forKey: "lat"), lon: defaults.double(forKey: "lon")))]
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.cities)
            for key in ["cityName", "lat", "lon"] { defaults.removeObject(forKey: key) }
        }
    }

    static var showTemperature: Bool {
        get { defaults.bool(forKey: Key.showTemperature) }
        set { defaults.set(newValue, forKey: Key.showTemperature) }
    }

    /// Panel and Settings follow macOS unless the user fixed light or dark.
    static func applyAppearance() {
        NSApp.appearance = switch defaults.string(forKey: Key.appearance) {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    static var alarmPolicy: AlarmPolicy {
        AlarmPolicy(soundEnabled: defaults.bool(forKey: Key.soundEnabled),
                    repeatUntilSeen: defaults.bool(forKey: Key.repeatUntilSeen),
                    quietYellowAtNight: defaults.bool(forKey: Key.quietYellowAtNight),
                    minimumLevel: AlertLevel(rawValue: defaults.integer(forKey: Key.minimumLevel)) ?? .yellow)
    }
}
