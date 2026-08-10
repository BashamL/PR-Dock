import Combine
import Foundation
import Testing
@testable import PRDock

@Suite("Dock geometry")
struct DockGeometryTests {
    @Test func detectsBottomDockAndAnchorsTrailing() {
        let geometry = DockGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 80, width: 1440, height: 795)
        )

        #expect(geometry.edge == .bottom)
        #expect(geometry.dockInset == 80)
        #expect(geometry.collapsedHeight == 72)

        let frame = geometry.frame(
            for: CGSize(width: 292, height: geometry.collapsedHeight),
            side: .trailing
        )
        #expect(frame.maxX == 1428)
        #expect(frame.minY == 4)
    }

    @Test func detectsSideDocks() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = DockGeometry(
            screenFrame: screen,
            visibleFrame: CGRect(x: 76, y: 0, width: 1364, height: 875)
        )
        let right = DockGeometry(
            screenFrame: screen,
            visibleFrame: CGRect(x: 0, y: 0, width: 1364, height: 875)
        )

        #expect(left.edge == .left)
        #expect(right.edge == .right)
        #expect(
            left.frame(for: CGSize(width: 292, height: 56), side: .automatic).minX
                == 88
        )
        #expect(
            right.frame(for: CGSize(width: 292, height: 56), side: .automatic).maxX
                == 1352
        )
    }

    @Test func hiddenDockFallsBackToScreenEdge() {
        let geometry = DockGeometry(
            screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        )

        #expect(geometry.edge == .hidden)
        let frame = geometry.frame(
            for: CGSize(width: 292, height: 56),
            side: .leading
        )
        #expect(frame.minX == -1908)
        #expect(frame.minY == 12)
    }
}

@Suite("Pull request models")
struct PullRequestModelTests {
    @Test func statusPriorityAndMergeEligibility() {
        #expect(
            makePullRequest(mergeState: "DIRTY").presentationStatus.label
                == "Has conflicts"
        )
        #expect(
            makePullRequest(reviewDecision: "CHANGES_REQUESTED")
                .presentationStatus.label == "Changes requested"
        )

        let ready = makePullRequest()
        #expect(ready.presentationStatus.label == "Ready to merge")
        #expect(ready.presentationStatus.canMerge)
        #expect(ready.group == .ready)
    }

    @Test func reviewRequestIsNeverDirectlyMergeable() {
        let review = makePullRequest(scope: .reviewRequested)
        #expect(!review.presentationStatus.canMerge)
        #expect(review.group == .reviewRequests)
    }

    @Test func runningChecksTakePriorityOverBlockedMergeState() {
        let running = makePullRequest(
            mergeState: "BLOCKED",
            checkState: "PENDING"
        )
        let blocked = makePullRequest(
            mergeState: "BLOCKED",
            checkState: "NONE"
        )

        #expect(running.presentationStatus.label == "Checks running")
        #expect(blocked.presentationStatus.label == "Merge blocked")
    }

    @Test func decodesGitHubPayload() throws {
        let data = """
        {
          "viewer": "octocat",
          "rateLimit": {"remaining": 4999, "resetAt": "2026-08-05T01:00:00Z"},
          "prs": [{
            "title": "Ship v2",
            "url": "https://github.com/acme/app/pull/42",
            "number": 42,
            "scope": "reviewRequested",
            "author": {"login": "hubot"},
            "isDraft": false,
            "createdAt": "2026-08-01T00:00:00Z",
            "updatedAt": "2026-08-04T00:00:00Z",
            "headRefName": "v2",
            "baseRefName": "main",
            "reviewDecision": "REVIEW_REQUIRED",
            "mergeStateStatus": "BLOCKED",
            "additions": 10,
            "deletions": 2,
            "comments": {"totalCount": 3},
            "labels": {"nodes": [{"name": "release", "color": "00ff00"}]},
            "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]},
            "repository": {"nameWithOwner": "acme/app"}
          }]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GitHubPayload.self, from: data)

        #expect(payload.viewer == "octocat")
        #expect(payload.prs.first?.scope == .reviewRequested)
        #expect(payload.prs.first?.comments.totalCount == 3)
        #expect(payload.rateLimit?.remaining == 4999)
    }

    @Test func classifiesActionableGitHubErrors() {
        #expect(
            GitHubServiceError.classify(commandOutput: "not logged into github.com")
                == .notAuthenticated
        )
        #expect(
            GitHubServiceError.classify(commandOutput: "API rate limit exceeded")
                == .rateLimited
        )
        #expect(
            GitHubServiceError.classify(commandOutput: "could not resolve host")
                == .network("could not resolve host")
        )
    }
}

@Suite("Settings and view model", .serialized)
struct SettingsAndViewModelTests {
    @Test @MainActor
    func settingsPersistAndClampRefreshInterval() {
        let suiteName = "PRDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.dockSide = .leading
        settings.refreshIntervalMinutes = 90
        settings.showsReviewRequests = false

        let restored = AppSettings(defaults: defaults)
        #expect(restored.dockSide == .leading)
        #expect(restored.refreshIntervalMinutes == 30)
        #expect(!restored.showsReviewRequests)
    }

    @Test @MainActor
    func viewModelGroupsAndFiltersFetchedPullRequests() async {
        let suiteName = "PRDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let payload = GitHubPayload(
            viewer: "octocat",
            rateLimit: RateLimit(remaining: 5000, resetAt: nil),
            prs: [
                makePullRequest(
                    number: 1,
                    lastPushAt: Date(timeIntervalSince1970: 300)
                ),
                makePullRequest(
                    number: 2,
                    scope: .reviewRequested,
                    lastPushAt: Date(timeIntervalSince1970: 400)
                ),
                makePullRequest(
                    number: 3,
                    checkState: "FAILURE",
                    lastPushAt: Date(timeIntervalSince1970: 100)
                ),
            ]
        )
        let model = PRDockViewModel(
            settings: settings,
            cache: MemoryCache(),
            serviceFactory: { _ in StubGitHubService(payload: payload) }
        )

        model.start()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.pullRequests.count == 3)
        #expect(model.readyCount == 1)
        #expect(model.reviewRequestCount == 1)
        #expect(model.attentionCount == 1)
        #expect(model.latestAuthoredPullRequest?.number == 1)
        #expect(model.orderedPullRequests.map(\.number) == [3, 1, 2])

        settings.showsReviewRequests = false
        #expect(model.pullRequests.count == 2)
    }

    @Test @MainActor
    func viewModelKeepsCachedDataWhenRefreshFails() async {
        let suiteName = "PRDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let payload = GitHubPayload(
            viewer: "octocat",
            rateLimit: nil,
            prs: [makePullRequest()]
        )
        let model = PRDockViewModel(
            settings: AppSettings(defaults: defaults),
            cache: MemoryCache(payload: payload),
            serviceFactory: { _ in FailingGitHubService() }
        )

        model.start()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.pullRequests.count == 1)
        #expect(model.isShowingStaleData)
        #expect(model.errorMessage == "GitHub could not be reached.")
    }

    @Test @MainActor
    func presentationChangesOnlyThroughExplicitActions() {
        let suiteName = "PRDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PRDockViewModel(
            settings: AppSettings(defaults: defaults),
            cache: MemoryCache(),
            serviceFactory: { _ in
                StubGitHubService(
                    payload: GitHubPayload(viewer: "", rateLimit: nil, prs: [])
                )
            }
        )

        #expect(model.presentation == .collapsed)
        var presentationAtInvalidation: DockPresentation?
        let cancellable = model.objectWillChange.sink {
            presentationAtInvalidation = model.presentation
        }

        model.expand()
        #expect(model.presentation == .expanded)
        #expect(presentationAtInvalidation == .expanded)
        model.collapse()
        #expect(model.presentation == .collapsed)
        #expect(presentationAtInvalidation == .collapsed)
        model.toggleExpanded()
        #expect(model.presentation == .expanded)
        #expect(presentationAtInvalidation == .expanded)
        withExtendedLifetime(cancellable) {}
    }

    @Test @MainActor
    func controllerAppliesCurrentFrameAndCollapsesForOutsideClick() async {
        let suiteName = "PRDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PRDockViewModel(
            settings: AppSettings(defaults: defaults),
            cache: MemoryCache(),
            serviceFactory: { _ in
                StubGitHubService(
                    payload: GitHubPayload(viewer: "", rateLimit: nil, prs: [])
                )
            }
        )
        let controller = FloatingPanelController(model: model)

        #expect(controller.panelFrame.width == 440)
        #expect(
            !controller.panelCollectionBehavior.contains(.fullScreenAuxiliary)
        )

        model.expand()
        try? await Task.sleep(for: .milliseconds(350))
        #expect(controller.panelFrame.width == 440)

        controller.collapseForOutsideClick(
            at: CGPoint(
                x: controller.panelFrame.maxX + 100,
                y: controller.panelFrame.maxY + 100
            )
        )
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.presentation == .collapsed)
        #expect(controller.panelFrame.width == 440)

        controller.toggleVisibility()
    }
}

@Suite("Pull request cache")
struct PullRequestCacheTests {
    @Test func cacheRoundTripAndClear() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRDockTests-\(UUID().uuidString).json")
        let cache = PullRequestCache(fileURL: url)
        let payload = GitHubPayload(
            viewer: "octocat",
            rateLimit: nil,
            prs: [makePullRequest()]
        )

        await cache.save(payload)
        let loaded = await cache.load()
        #expect(loaded?.payload.viewer == "octocat")
        #expect(loaded?.payload.prs.count == 1)

        await cache.clear()
        let cleared = await cache.load()
        #expect(cleared == nil)
    }

    @Test func rejectsOldCacheVersion() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRDockTests-\(UUID().uuidString).json")
        let oldCache = """
        {"version":1,"savedAt":"2026-08-05T00:00:00Z","payload":{"viewer":"","rateLimit":null,"prs":[]}}
        """
        try Data(oldCache.utf8).write(to: url)

        let cache = PullRequestCache(fileURL: url)
        #expect(await cache.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

private struct StubGitHubService: GitHubServing {
    let payload: GitHubPayload

    func fetchPullRequests() async throws -> GitHubPayload { payload }
    func squashMerge(_ pullRequest: PullRequest) async throws {}
}

private struct FailingGitHubService: GitHubServing {
    func fetchPullRequests() async throws -> GitHubPayload {
        throw GitHubServiceError.network("")
    }
    func squashMerge(_ pullRequest: PullRequest) async throws {}
}

private actor MemoryCache: PullRequestCaching {
    private var snapshot: CachedPullRequests?

    init(payload: GitHubPayload? = nil) {
        snapshot = payload.map { CachedPullRequests(payload: $0) }
    }

    func load() async -> CachedPullRequests? { snapshot }
    func save(_ payload: GitHubPayload) async {
        snapshot = CachedPullRequests(payload: payload)
    }
    func clear() async { snapshot = nil }
}

private func makePullRequest(
    number: Int = 1,
    scope: PullRequestScope = .authored,
    reviewDecision: String? = "APPROVED",
    mergeState: String? = "CLEAN",
    checkState: String = "SUCCESS",
    lastPushAt: Date? = nil
) -> PullRequest {
    PullRequest(
        title: "Improve PR Dock",
        url: URL(string: "https://github.com/acme/app/pull/\(number)")!,
        number: number,
        scope: scope,
        author: .init(login: "octocat"),
        isDraft: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_100_000 + Double(number)),
        headRefName: "feature-\(number)",
        baseRefName: "main",
        reviewDecision: reviewDecision,
        mergeStateStatus: mergeState,
        additions: 20,
        deletions: 4,
        comments: .init(totalCount: 2),
        labels: .init(nodes: []),
        commits: .init(
            nodes: [
                .init(
                    commit: .init(
                        committedDate: lastPushAt,
                        statusCheckRollup: .init(state: checkState)
                    )
                ),
            ]
        ),
        repository: .init(nameWithOwner: "acme/app")
    )
}
