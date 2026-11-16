import Foundation
import SMNCore

/// User settings. Keys are the ones 1.0 used, so existing installs keep their city.
@MainActor
enum Preferences {
    private static var defaults: UserDefaults { .standard }

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

    static var soundEnabled: Bool {
        get { !defaults.bool(forKey: "soundOff") }
        set { defaults.set(!newValue, forKey: "soundOff") }
    }
}
