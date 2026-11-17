import AppKit
import os
import SMNCore

let log = Logger(subsystem: "local.smnalertas", category: "app")

/// Creates the model and the two pieces of UI, and wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private lazy var statusItem = StatusItemController(model: model)
    private lazy var settings = SettingsWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        #if DEV_TOOLS
        Snapshots.runIfRequested()
        #endif
        NSApp.mainMenu = Self.mainMenu()
        model.onAlarm = { [unowned self] level, reaction in statusItem.startAlarm(level, reaction) }
        model.onOpenPanel = { [unowned self] in statusItem.showPopover() }
        model.onSilence = { [unowned self] in statusItem.stopAlarm() }
        model.onOpenSettings = { [unowned self] in settings.show() }
        _ = statusItem
        model.start()
    }

    /// Menu-bar-only apps have no visible menu, but text fields still need ⌘C/⌘V and windows ⌘W.
    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Salir de SMN Alertas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: "Ventana")
        window.addItem(withTitle: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        for submenu in [app, edit, window] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}
