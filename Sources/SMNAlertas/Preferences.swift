import Foundation
import SMNCore

/// User settings. The toggles are read with @AppStorage in Settings using these same keys.
@MainActor
enum Preferences {
    enum Key {
        static let soundEnabled = "soundEnabled"
        static let repeatUntilSeen = "repeatUntilSeen"
        static let quietYellowAtNight = "quietYellowAtNight"
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        // 1.0 stored the inverse ("soundOff"); carry it over once.
        if defaults.object(forKey: "soundOff") != nil {
            defaults.set(!defaults.bool(forKey: "soundOff"), forKey: Key.soundEnabled)
            defaults.removeObject(forKey: "soundOff")
        }
        defaults.register(defaults: [Key.soundEnabled: true, Key.repeatUntilSeen: true, Key.quietYellowAtNight: false])
    }

    /// Keys kept from 1.0 so existing installs keep their city.
    static var city: City? {
        get {
            guard let name = defaults.string(forKey: "cityName") else { return nil }
            return City(name: name, coordinate: Coordinate(lat: defaults.double(forKey: "lat"),
                                                           lon: defaults.double(forKey: "lon")))
        }
        set {
            defaults.set(newValue?.name, forKey: "cityName")
            defaults.set(newValue?.coordinate.lat, forKey: "lat")
            defaults.set(newValue?.coordinate.lon, forKey: "lon")
        }
    }

    static var alarmPolicy: AlarmPolicy {
        AlarmPolicy(soundEnabled: defaults.bool(forKey: Key.soundEnabled),
                    repeatUntilSeen: defaults.bool(forKey: Key.repeatUntilSeen),
                    quietYellowAtNight: defaults.bool(forKey: Key.quietYellowAtNight))
    }
}
