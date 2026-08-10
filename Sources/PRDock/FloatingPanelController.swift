@preconcurrency import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class FloatingPanelController {
    private enum Metrics {
        static let collapsedWidth: CGFloat = 292
        static let expandedWidth: CGFloat = 440
    }

    private let model: PRDockViewModel
    private let panel: DockPanel
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private let eventMonitors = EventMonitorTokens()

    var panelFrame: CGRect { panel.frame }

    init(model: PRDockViewModel) {
        self.model = model
        panel = DockPanel(
            contentRect: CGRect(x: 0, y: 0, width: Metrics.collapsedWidth, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        observeState()
        movePanel(animated: false)
        panel.orderFrontRegardless()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        eventMonitors.removeAll()
    }

    func toggleVisibility() {
        if panel.isVisible {
            model.collapse()
            panel.orderOut(nil)
        } else {
            movePanel(animated: false, preferPointerScreen: true)
            panel.orderFrontRegardless()
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.sharingType = .readOnly
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        let containerView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        containerView.autoresizingMask = [.width, .height]

        let hostingView = NSHostingView(
            rootView: PRDockRootView(model: model, settings: model.settings)
        )
        hostingView.sizingOptions = []
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        panel.contentView = containerView

        installOutsideClickMonitors()

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.model.pendingMerge == nil else { return }
                    self.model.collapse()
                }
            }
        )

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.movePanel(animated: false) }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
        ] {
            workspaceObservers.append(
                workspaceCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.movePanel(animated: false) }
                }
            )
        }
    }

    private func observeState() {
        model.presentationDidChange
            .sink { [weak self] presentation in
                guard let self else { return }
                self.movePanel(for: presentation, animated: true)
                if presentation.isExpanded {
                    self.panel.makeKeyAndOrderFront(nil)
                }
            }
            .store(in: &cancellables)

        model.$pullRequests
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.model.isExpanded == true else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.movePanel(for: self.model.presentation, animated: true)
                }
            }
            .store(in: &cancellables)

        model.settings.$dockSide
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] side in
                self?.movePanel(
                    for: self?.model.presentation ?? .collapsed,
                    side: side,
                    animated: true
                )
            }
            .store(in: &cancellables)
    }

    private func movePanel(
        for presentation: DockPresentation? = nil,
        side: DockSidePreference? = nil,
        animated: Bool,
        preferPointerScreen: Bool = false
    ) {
        guard let screen = targetScreen(preferPointerScreen: preferPointerScreen) else {
            return
        }

        let targetPresentation = presentation ?? model.presentation
        let targetSide = side ?? model.settings.dockSide
        let geometry = DockGeometry(screen: screen)
        let size = targetPresentation.isExpanded
            ? CGSize(width: Metrics.expandedWidth, height: model.expandedHeight)
            : CGSize(width: Metrics.collapsedWidth, height: geometry.collapsedHeight)
        let targetFrame = geometry.frame(for: size, side: targetSide)

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = targetPresentation.isExpanded ? 0.24 : 0.18
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20,
                0.88,
                0.20,
                1
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func installOutsideClickMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        eventMonitors.local = NSEvent.addLocalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            Task { @MainActor in
                self?.collapseForOutsideClick(at: NSEvent.mouseLocation)
            }
            return event
        }

        eventMonitors.global = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapseForOutsideClick(at: NSEvent.mouseLocation)
            }
        }
    }

    func collapseForOutsideClick(at location: CGPoint) {
        guard model.isExpanded,
              model.pendingMerge == nil,
              !panel.frame.contains(location) else {
            return
        }
        model.collapse()
    }

    private func targetScreen(preferPointerScreen: Bool) -> NSScreen? {
        if preferPointerScreen {
            let pointer = NSEvent.mouseLocation
            if let pointerScreen = NSScreen.screens.first(
                where: { $0.frame.contains(pointer) }
            ) {
                return pointerScreen
            }
        }
        return panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class EventMonitorTokens: @unchecked Sendable {
    var local: Any?
    var global: Any?

    func removeAll() {
        if let local {
            NSEvent.removeMonitor(local)
            self.local = nil
        }
        if let global {
            NSEvent.removeMonitor(global)
            self.global = nil
        }
    }
}
