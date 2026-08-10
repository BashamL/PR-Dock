import Foundation

struct CachedPullRequests: Codable, Sendable {
    static let currentVersion = 2

    let version: Int
    let savedAt: Date
    let payload: GitHubPayload

    init(savedAt: Date = .now, payload: GitHubPayload) {
        version = Self.currentVersion
        self.savedAt = savedAt
        self.payload = payload
    }
}

protocol PullRequestCaching: Sendable {
    func load() async -> CachedPullRequests?
    func save(_ payload: GitHubPayload) async
    func clear() async
}

actor PullRequestCache: PullRequestCaching {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.fileURL = applicationSupport
                .appendingPathComponent("PR Dock", isDirectory: true)
                .appendingPathComponent("pull-requests-v2.json")
        }
    }

    func load() async -> CachedPullRequests? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(CachedPullRequests.self, from: data),
              snapshot.version == CachedPullRequests.currentVersion else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return snapshot
    }

    func save(_ payload: GitHubPayload) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(CachedPullRequests(payload: payload))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache failures must never block fresh GitHub data.
        }
    }

    func clear() async {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
