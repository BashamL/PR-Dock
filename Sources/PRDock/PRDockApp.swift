import AppKit
import Combine
import SwiftUI

@main
struct PRDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: appDelegate.settings,
                model: appDelegate.model
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let model: PRDockViewModel

    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var statusSummaryItem: NSMenuItem?
    private var visibilityItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        let settings = AppSettings()
        self.settings = settings
        model = PRDockViewModel(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = FloatingPanelController(model: model)
        configureStatusItem()
        observeModel()
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent,
              let button = statusItem?.button else {
            return
        }

        if event.type == .rightMouseUp {
            updateMenu()
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.maxY + 4),
                in: button
            )
        } else {
            panelController?.toggleVisibility()
        }
    }

    @objc private func togglePanel() {
        panelController?.toggleVisibility()
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func openDashboard() {
        model.openDashboard()
    }

    @objc private func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "PR Dock — click to show or hide, right-click for menu"

        let summary = NSMenuItem(title: "Waiting for first sync…", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        statusMenu.addItem(summary)
        statusSummaryItem = summary

        statusMenu.addItem(.separator())

        let visibility = statusMenu.addItem(
            withTitle: "Show or Hide PR Dock",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        visibilityItem = visibility
        statusMenu.addItem(
            withTitle: "Refresh Pull Requests",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        statusMenu.addItem(
            withTitle: "Open GitHub Pull Requests",
            action: #selector(openDashboard),
            keyEquivalent: ""
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit PR Dock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        statusMenu.items.forEach { $0.target = self }
        statusItem = item
        updateMenu()
    }

    private func observeModel() {
        Publishers.CombineLatest3(
            model.$pullRequests,
            model.$syncState,
            model.$lastUpdated
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.updateMenu()
            self?.updateStatusIcon()
        }
        .store(in: &cancellables)
    }

    private func updateMenu() {
        let count = model.pullRequests.count
        if model.isLoading {
            statusSummaryItem?.title = "Refreshing \(count) pull requests…"
        } else if let message = model.errorMessage {
            statusSummaryItem?.title = message
        } else if let lastUpdated = model.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            statusSummaryItem?.title =
                "\(count) pull requests · synced "
                + formatter.localizedString(for: lastUpdated, relativeTo: .now)
        } else {
            statusSummaryItem?.title = "\(count) pull requests"
        }
    }

    private func updateStatusIcon() {
        let symbol: String
        if model.attentionCount > 0 {
            symbol = "exclamationmark.triangle"
        } else if model.readyCount > 0 {
            symbol = "arrow.triangle.merge"
        } else {
            symbol = "arrow.triangle.pull"
        }
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "PR Dock"
        )
    }
}
