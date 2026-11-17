import AppKit

/// Sparkle refuses to update an app run from Downloads (or from the read-only copy macOS runs it from
/// there), so when launched outside an Applications folder, offer once to move it to /Applications.
@MainActor
enum MoveToApplications {
    private static let declinedKey = "declinedMoveToApplications"

    /// Returns true when it is relaunching from /Applications and this instance is about to quit.
    static func offerIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path + "/"
        guard !source.path.hasPrefix("/Applications/"), !source.path.hasPrefix(userApps),
              !UserDefaults.standard.bool(forKey: declinedKey) else { return false }

        NSApp.activate(ignoringOtherApps: true)          // menu bar apps start in the background
        let ask = NSAlert()
        ask.messageText = "¿Mover SMN Alertas a Aplicaciones?"
        ask.informativeText = "Desde ahí puede actualizarse sola y queda junto a tus otras apps."
        ask.addButton(withTitle: "Mover a Aplicaciones")
        ask.addButton(withTitle: "No mover")
        guard ask.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return false
        }

        let destination = URL(fileURLWithPath: "/Applications").appending(path: source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)   // an older version
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            let fail = NSAlert()
            fail.messageText = "No se pudo mover"
            fail.informativeText = "Arrastrá SMN Alertas a la carpeta Aplicaciones desde el Finder.\n\n\(error.localizedDescription)"
            fail.runModal()
            return false
        }
        // The user already opened it, so drop the download mark: otherwise macOS would run the copy
        // from a read-only location again and Sparkle still couldn't update it.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? xattr.run()
        xattr.waitUntilExit()
        // From the read-only copy we can't reach the original in Downloads; leaving it there is harmless.
        if !source.path.contains("/AppTranslocation/") {
            try? FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return true
    }
}
