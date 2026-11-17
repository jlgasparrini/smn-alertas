import AppKit
import Combine
import SMNCore
import SwiftUI

/// The menu bar icon, its blinking "alarm", and the popover with the panel.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: AppModel
    private var alarmTask: Task<Void, Never>?
    /// Icon with and without the level dot, rebuilt only when the state changes: blinking just swaps them.
    private var icons: (dot: NSImage, noDot: NSImage)?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        super.init()
        let host = NSHostingController(rootView: PanelView().environmentObject(model))
        host.sizingOptions = .preferredContentSize       // popover follows the panel's height
        popover.contentViewController = host
        popover.behavior = .transient                    // closes on click outside, like system menu extras
        popover.delegate = self
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        updateIcon()
        // objectWillChange fires before the change; read the new state on the next run loop pass.
        model.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon() }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverWillShow(_ notification: Notification) { stopAlarm() }

    /// Blink the level dot until the panel is opened; with `.sound(repeating: true)` the sound repeats
    /// every 4 s for up to 2 min so an empty room doesn't chime forever.
    func startAlarm(_ level: AlertLevel, _ reaction: AlarmPolicy.Reaction) {
        stopAlarm()
        log.notice("alarm \(level.name(), privacy: .public) \(String(describing: reaction), privacy: .public)")
        guard !popover.isShown else { return }           // already looking at it
        if case .sound = reaction { model.notifier.playSound(for: level) }
        alarmTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                tick += 1
                item.button?.image = tick % 2 == 0 ? icons?.dot : icons?.noDot
                if case .sound(repeating: true) = reaction, tick % 8 == 0, tick <= 240 {
                    model.notifier.playSound(for: level)
                }
            }
        }
    }

    func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        item.button?.image = icons?.dot
    }

    private func updateIcon() {
        guard let button = item.button else { return }
        let alert = mostSevere(model.alerts)
        let icons = (dot: menuBarImage(for: alert), noDot: menuBarImage(for: alert, dotVisible: false))
        self.icons = icons
        if alarmTask == nil { button.image = icons.dot }          // while blinking, the next tick picks it up
        let temperature = model.showTemperature ? model.places.first?.current?.temperatureText : nil
        button.title = temperature ?? ""
        button.imagePosition = temperature == nil ? .imageOnly : .imageLeading
    }
}
