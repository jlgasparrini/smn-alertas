#if DEV_TOOLS
import AppKit
import SMNCore
import SwiftUI

/// `SMNAlertas --snapshots <dir>` (development builds): renders the panel for every demo state and
/// the Settings window, in light and dark, to PNGs. Lets you review the UI without screen-capture access.
@MainActor
enum Snapshots {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel()
        for (n, state) in DemoState.all.enumerated() {
            model.runDemo(state, announce: false)
            render(PanelView().environmentObject(model), to: dir, name: "panel-\(n)")
        }
        render(SettingsView().environmentObject(model), to: dir, name: "settings")
        exit(0)
    }

    private static func render(_ view: some View, to dir: URL, name: String) {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // cacheDisplay skips the window background, so paint it into the view.
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: appearance)
            host.frame.size = host.fittingSize
            // An offscreen window gives the view a real backing and appearance, like the popover does.
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = host.appearance
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))      // let Charts and fonts settle
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appending(path: "\(name)-\(suffix).png"))
        }
    }
}
#endif
