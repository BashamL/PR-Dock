@preconcurrency import AppKit
import Combine
import Foundation

enum DockPresentation: Equatable, Sendable {
    case collapsed
    case expanded

    var isExpanded: Bool {
        self == .expanded
    }
}

enum SyncState: Equatable, Sendable {
    case idle
    case refreshing
    case stale(String)
    case setupRequired(String)
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .refreshing: nil
        case .stale(let message),
             .setupRequired(let message),
             .failed(let message):
            message
        }
    }
}

@MainActor
final class PRDockViewModel: ObservableObject {
    typealias ServiceFactory = @MainActor (URL?) -> any GitHubServing

    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var viewer = ""
    @Published private(set) var rateLimit: RateLimit?
    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var mergingIDs: Set<URL> = []
    @Published private(set) var lastUpdated: Date?
    private(set) var presentation: DockPresentation
    @Published var pendingMerge: PullRequest?

    let settings: AppSettings
    let presentationDidChange = PassthroughSubject<DockPresentation, Never>()

    private let cache: any PullRequestCaching
    private let serviceFactory: ServiceFactory
    private var allPullRequests: [PullRequest] = []
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        settings: AppSettings = AppSettings(),
        cache: any PullRequestCaching = PullRequestCache(),
        serviceFactory: @escaping ServiceFactory = {
            GitHubService(executableURL: $0)
        }
    ) {
        self.settings = settings
        self.cache = cache
        self.serviceFactory = serviceFactory
        presentation = .collapsed
        observeSettings()
        observeWorkspace()
    }

    deinit {
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    var isExpanded: Bool { presentation.isExpanded }
    var isLoading: Bool { syncState == .refreshing }
    var isShowingStaleData: Bool {
        if case .stale = syncState { return true }
        return false
    }
    var errorMessage: String? { syncState.message }
    var rateLimitRemaining: Int? { rateLimit?.remaining }

    var groupedPullRequests: [(group: PullRequestGroup, items: [PullRequest])] {
        PullRequestGroup.allCases.compactMap { group in
            let items = pullRequests
                .filter { $0.group == group }
                .sorted(by: Self.order)
            return items.isEmpty ? nil : (group, items)
        }
    }

    var expandedHeight: CGFloat {
        let visibleRows = min(max(pullRequests.count, 1), 6)
        let sectionCount = groupedPullRequests.count
        return min(720, CGFloat(178 + visibleRows * 76 + sectionCount * 27))
    }

    var readyCount: Int {
        pullRequests.filter { $0.group == .ready }.count
    }

    var attentionCount: Int {
        pullRequests.filter { $0.group == .attention }.count
    }

    var reviewRequestCount: Int {
        pullRequests.filter { $0.group == .reviewRequests }.count
    }

    var waitingCount: Int {
        pullRequests.filter { $0.group == .waiting }.count
    }

    func start() {
        Task {
            if let cached = await cache.load() {
                apply(cached.payload)
                lastUpdated = cached.savedAt
                syncState = .stale("Showing the last successful sync.")
            }
            refresh()
        }
        restartPolling()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    func expand() {
        setPresentation(.expanded)
    }

    func collapse() {
        setPresentation(.collapsed)
    }

    func toggleExpanded() {
        setPresentation(isExpanded ? .collapsed : .expanded)
    }

    func open(_ pullRequest: PullRequest) {
        NSWorkspace.shared.open(pullRequest.url)
    }

    func openDashboard() {
        guard var components = URLComponents(string: "https://github.com/pulls") else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "is:open is:pr involves:@me"),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMerge(_ pullRequest: PullRequest) {
        guard pullRequest.presentationStatus.canMerge else { return }
        pendingMerge = pullRequest
    }

    func cancelMerge() {
        pendingMerge = nil
    }

    func confirmMerge() {
        guard let requestedPullRequest = pendingMerge else { return }
        pendingMerge = nil
        mergingIDs.insert(requestedPullRequest.id)

        Task {
            defer { mergingIDs.remove(requestedPullRequest.id) }
            do {
                let service = makeService()
                let latestPayload = try await service.fetchPullRequests()
                apply(latestPayload)
                await cache.save(latestPayload)

                guard let latest = latestPayload.prs.first(
                    where: { $0.id == requestedPullRequest.id }
                ), latest.presentationStatus.canMerge else {
                    syncState = .failed(
                        "This pull request is no longer ready to merge. Its status was refreshed."
                    )
                    return
                }

                try await service.squashMerge(latest)
                NSSound(named: "Glass")?.play()
                refresh()
            } catch {
                syncState = .failed("Merge failed: \(error.localizedDescription)")
            }
        }
    }

    func clearCache() {
        Task { await cache.clear() }
    }

    private func performRefresh() async {
        syncState = .refreshing
        do {
            let payload = try await makeService().fetchPullRequests()
            try Task.checkCancellation()
            apply(payload)
            lastUpdated = .now
            syncState = .idle
            await cache.save(payload)
            restartPolling()
        } catch is CancellationError {
            return
        } catch let error as GitHubServiceError {
            let message = error.localizedDescription
            switch error {
            case .cliNotFound, .notAuthenticated:
                syncState = .setupRequired(message)
            default:
                syncState = pullRequests.isEmpty ? .failed(message) : .stale(message)
            }
        } catch {
            let message = error.localizedDescription
            syncState = pullRequests.isEmpty ? .failed(message) : .stale(message)
        }
    }

    private func setPresentation(_ newPresentation: DockPresentation) {
        guard presentation != newPresentation else { return }
        presentation = newPresentation
        objectWillChange.send()
        presentationDidChange.send(newPresentation)
    }

    private func apply(_ payload: GitHubPayload) {
        allPullRequests = payload.prs
        viewer = payload.viewer
        rateLimit = payload.rateLimit
        applyScopeFilter()
    }

    private func applyScopeFilter() {
        applyScopeFilter(
            showsAuthored: settings.showsAuthored,
            showsReviewRequests: settings.showsReviewRequests
        )
    }

    private func applyScopeFilter(
        showsAuthored: Bool,
        showsReviewRequests: Bool
    ) {
        pullRequests = allPullRequests.filter { pullRequest in
            switch pullRequest.scope {
            case .authored: showsAuthored
            case .reviewRequested: showsReviewRequests
            }
        }
    }

    private func makeService() -> any GitHubServing {
        serviceFactory(settings.resolvedGitHubCLIURL())
    }

    private func observeSettings() {
        settings.$showsAuthored
            .combineLatest(settings.$showsReviewRequests)
            .dropFirst()
            .sink { [weak self] authored, reviews in
                self?.applyScopeFilter(
                    showsAuthored: authored,
                    showsReviewRequests: reviews
                )
            }
            .store(in: &cancellables)

        settings.$refreshIntervalMinutes
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.restartPolling() }
            .store(in: &cancellables)

        settings.$customGitHubCLIPath
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        )
    }

    private func restartPolling() {
        pollingTask?.cancel()
        let interval = nextRefreshInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private var nextRefreshInterval: Duration {
        if let rateLimit,
           rateLimit.remaining < 100,
           let resetAt = rateLimit.resetAt,
           resetAt > Date.now {
            return .seconds(max(resetAt.timeIntervalSinceNow, 60))
        }
        return .seconds(settings.refreshIntervalMinutes * 60)
    }

    private static func order(_ lhs: PullRequest, _ rhs: PullRequest) -> Bool {
        if lhs.presentationStatus.rank != rhs.presentationStatus.rank {
            return lhs.presentationStatus.rank < rhs.presentationStatus.rank
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
