import AppKit
import SwiftUI

@main
struct PRDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PRDockViewModel()
    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = FloatingPanelController(model: model)
        configureStatusItem()
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func togglePanel() {
        panelController?.toggleVisibility()
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "arrow.triangle.pull",
            accessibilityDescription: "PR Dock"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Show or Hide PR Dock",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Refresh Pull Requests",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit PR Dock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }
}
