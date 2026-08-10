import AppKit

enum DockEdge: String, Sendable {
    case bottom
    case left
    case right
    case hidden
}

struct DockGeometry: Equatable, Sendable {
    static let edgeInset: CGFloat = 12
    static let minimumDockInset: CGFloat = 20

    let screenFrame: CGRect
    let visibleFrame: CGRect
    let edge: DockEdge
    let dockInset: CGFloat

    init(screenFrame: CGRect, visibleFrame: CGRect) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame

        let leftInset = max(0, visibleFrame.minX - screenFrame.minX)
        let rightInset = max(0, screenFrame.maxX - visibleFrame.maxX)
        let bottomInset = max(0, visibleFrame.minY - screenFrame.minY)

        if leftInset > Self.minimumDockInset {
            edge = .left
            dockInset = leftInset
        } else if rightInset > Self.minimumDockInset {
            edge = .right
            dockInset = rightInset
        } else if bottomInset > Self.minimumDockInset {
            edge = .bottom
            dockInset = bottomInset
        } else {
            edge = .hidden
            dockInset = 0
        }
    }

    var collapsedHeight: CGFloat {
        guard edge == .bottom else { return 56 }
        return min(max(dockInset - 8, 48), 76)
    }

    func frame(for size: CGSize, side: DockSidePreference) -> CGRect {
        let resolvedSide: DockSidePreference
        switch side {
        case .automatic:
            resolvedSide = edge == .left ? .leading : .trailing
        case .leading, .trailing:
            resolvedSide = side
        }

        let horizontalBounds: CGRect
        switch edge {
        case .left, .right:
            horizontalBounds = visibleFrame
        case .bottom, .hidden:
            horizontalBounds = screenFrame
        }

        let originX: CGFloat
        if resolvedSide == .leading {
            originX = horizontalBounds.minX + Self.edgeInset
        } else {
            originX = horizontalBounds.maxX - size.width - Self.edgeInset
        }

        let originY: CGFloat
        switch edge {
        case .bottom:
            originY = screenFrame.minY + max(2, (dockInset - collapsedHeight) / 2)
        case .left, .right:
            originY = visibleFrame.minY + Self.edgeInset
        case .hidden:
            originY = screenFrame.minY + Self.edgeInset
        }

        return CGRect(origin: CGPoint(x: originX, y: originY), size: size)
    }
}

extension DockGeometry {
    init(screen: NSScreen) {
        self.init(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}
