import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class FloatingPanelController {
    private enum Metrics {
        static let collapsedSize = CGSize(width: 268, height: 56)
        static let expandedWidth: CGFloat = 420
        static let edgeSpacing: CGFloat = 14
    }

    private let model: PRDockViewModel
    private let panel: DockPanel
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var transitionWorkItems: [DispatchWorkItem] = []

    init(model: PRDockViewModel) {
        self.model = model

        let initialFrame = CGRect(origin: .zero, size: Metrics.collapsedSize)
        panel = DockPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        observeModel()
        movePanel(expanded: false, animated: false)
        panel.orderFrontRegardless()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            movePanel(expanded: model.isExpanded, animated: false)
            panel.orderFrontRegardless()
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.sharingType = .readOnly
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.acceptsMouseMovedEvents = true

        let containerView = HoverTrackingView(
            frame: CGRect(origin: .zero, size: Metrics.collapsedSize)
        )
        containerView.autoresizingMask = [.width, .height]
        containerView.onHoverChanged = { [weak self] hovering in
            self?.model.setHovering(hovering)
        }

        let hostingView = NSHostingView(rootView: PRDockRootView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        panel.contentView = containerView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.movePanel(expanded: self?.model.isExpanded ?? false, animated: false)
            }
        }
    }

    private func observeModel() {
        model.$isExpanded
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] expanded in
            self?.transitionPanel(to: expanded)
        }
        .store(in: &cancellables)

        model.$pullRequests
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.model.isExpanded else { return }
                self.movePanel(expanded: true, animated: true)
            }
            .store(in: &cancellables)
    }

    private func transitionPanel(to expanded: Bool) {
        transitionWorkItems.forEach { $0.cancel() }
        transitionWorkItems.removeAll()

        if expanded {
            model.setPresentedContent(expanded: false, visible: true)
            movePanel(expanded: true, animated: true)

            schedule(after: 0.01) {
                $0.model.setPresentedContent(expanded: false, visible: false)
            }
            schedule(after: 0.025) {
                $0.model.setPresentedContent(expanded: true, visible: false)
            }
            schedule(after: 0.032) {
                $0.model.setPresentedContent(expanded: true, visible: true)
            }
        } else {
            model.setPresentedContent(
                expanded: model.showsExpandedContent,
                visible: false
            )

            schedule(after: 0.015) {
                $0.model.setPresentedContent(expanded: false, visible: false)
                $0.movePanel(expanded: false, animated: true)
            }
            schedule(after: 0.025) {
                $0.model.setPresentedContent(expanded: false, visible: true)
            }
        }
    }

    private func schedule(
        after delay: TimeInterval,
        _ action: @escaping (FloatingPanelController) -> Void
    ) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            action(self)
        }
        transitionWorkItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func movePanel(expanded: Bool, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let size = expanded
            ? CGSize(width: Metrics.expandedWidth, height: model.expandedHeight)
            : Metrics.collapsedSize
        let targetFrame = frame(for: size, on: screen)

        guard animated else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.23 : 0.18
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20,
                0.90,
                0.20,
                1.0
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func frame(for size: CGSize, on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let rightDockInset = frame.maxX - visible.maxX
        let leftDockInset = visible.minX - frame.minX
        let bottomDockInset = visible.minY - frame.minY
        let hasSideDock = rightDockInset > 20 || leftDockInset > 20

        let centerX: CGFloat
        if rightDockInset > 20 {
            centerX = visible.maxX - Metrics.edgeSpacing - Metrics.expandedWidth / 2
        } else if leftDockInset > 20 {
            centerX = visible.minX + Metrics.edgeSpacing + Metrics.expandedWidth / 2
        } else {
            centerX = visible.maxX - Metrics.edgeSpacing - Metrics.expandedWidth / 2
        }

        let originY: CGFloat
        if bottomDockInset > 20 && !hasSideDock {
            originY = frame.minY + max(
                2,
                (bottomDockInset - Metrics.collapsedSize.height) / 2
            )
        } else {
            originY = visible.minY + Metrics.edgeSpacing
        }

        return CGRect(
            x: centerX - size.width / 2,
            y: originY,
            width: size.width,
            height: size.height
        )
    }
}

private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if hoverTrackingArea == nil {
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            hoverTrackingArea = trackingArea
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self, let window = self.window else { return }
            self.onHoverChanged?(window.frame.contains(NSEvent.mouseLocation))
        }
    }
}
