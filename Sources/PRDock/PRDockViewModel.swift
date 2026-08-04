import AppKit
import Combine
import Foundation

@MainActor
final class PRDockViewModel: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var viewer = ""
    @Published private(set) var rateLimitRemaining: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var mergingIDs: Set<URL> = []
    @Published var errorMessage: String?
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published private(set) var showsExpandedContent = false
    @Published private(set) var isContentVisible = true

    private let service = GitHubService()
    private var refreshTimer: AnyCancellable?
    private var hoverWorkItem: DispatchWorkItem?
    private var isHovered = false

    var recentPullRequests: [PullRequest] {
        Array(
            pullRequests
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(4)
        )
    }

    var orderedPullRequests: [PullRequest] {
        pullRequests.sorted {
            let left = $0.presentationStatus
            let right = $1.presentationStatus
            if left.rank != right.rank {
                return left.rank < right.rank
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var expandedHeight: CGFloat {
        let visibleRows = min(max(pullRequests.count, 1), 5)
        return min(680, CGFloat(188 + visibleRows * 82))
    }

    var readyCount: Int {
        pullRequests.filter { $0.presentationStatus.canMerge }.count
    }

    var attentionCount: Int {
        pullRequests.filter { $0.presentationStatus.tone == .danger }.count
    }

    var draftCount: Int {
        pullRequests.filter(\.isDraft).count
    }

    func start() {
        refresh()
        refreshTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let payload = try await service.fetchPullRequests()
                pullRequests = payload.prs
                viewer = payload.viewer
                rateLimitRemaining = payload.rateLimit?.remaining
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setHovering(_ hovering: Bool) {
        isHovered = hovering
        hoverWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if hovering {
                guard self.isHovered else { return }
                self.isExpanded = true
            } else if !self.isPinned {
                self.isExpanded = false
            }
        }

        hoverWorkItem = workItem
        let delay = hovering ? 0.0 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func togglePinned() {
        isPinned.toggle()
        if isPinned {
            isExpanded = true
        } else if !isHovered {
            isExpanded = false
        }
    }

    func setPresentedContent(expanded: Bool, visible: Bool) {
        showsExpandedContent = expanded
        isContentVisible = visible
    }

    func open(_ pullRequest: PullRequest) {
        NSWorkspace.shared.open(pullRequest.url)
    }

    func openDashboard() {
        guard !viewer.isEmpty else { return }
        var components = URLComponents(string: "https://github.com/pulls")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "is:open is:pr author:\(viewer)"),
        ]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }

    func merge(_ pullRequest: PullRequest) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Squash and merge #\(pullRequest.number)?"
        alert.informativeText = "\(pullRequest.repository.nameWithOwner)\n\nThis will merge the pull request immediately."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        mergingIDs.insert(pullRequest.id)
        Task {
            defer { mergingIDs.remove(pullRequest.id) }
            do {
                try await service.squashMerge(pullRequest)
                NSSound(named: "Glass")?.play()
                refresh()
            } catch {
                errorMessage = "Merge failed: \(error.localizedDescription)"
            }
        }
    }
}
