import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    Preferences.registerDefaults()          // before AppDelegate creates the model, which reads them
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)     // menu bar only, no Dock icon
    app.run()
}
