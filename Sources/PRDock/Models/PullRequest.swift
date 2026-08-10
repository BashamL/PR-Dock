import Foundation

struct GitHubPayload: Codable, Sendable {
    let viewer: String
    let rateLimit: RateLimit?
    let prs: [PullRequest]
}

struct RateLimit: Codable, Sendable {
    let remaining: Int
    let resetAt: Date?
}

enum PullRequestScope: String, Codable, Sendable {
    case authored
    case reviewRequested
}

struct PullRequest: Codable, Identifiable, Hashable, Sendable {
    struct Repository: Codable, Hashable, Sendable {
        let nameWithOwner: String
    }

    struct Actor: Codable, Hashable, Sendable {
        let login: String
    }

    struct LabelConnection: Codable, Hashable, Sendable {
        struct Label: Codable, Hashable, Sendable {
            let name: String
            let color: String
        }

        let nodes: [Label]
    }

    struct CommentConnection: Codable, Hashable, Sendable {
        let totalCount: Int
    }

    struct ReviewThreadConnection: Codable, Hashable, Sendable {
        struct ReviewThread: Codable, Hashable, Sendable {
            struct ReviewCommentConnection: Codable, Hashable, Sendable {
                struct ReviewComment: Codable, Hashable, Sendable {
                    let body: String
                    let url: URL
                    let author: Actor?
                }

                let nodes: [ReviewComment]
            }

            let isResolved: Bool
            let isOutdated: Bool
            let path: String
            let line: Int?
            let originalLine: Int?
            let comments: ReviewCommentConnection
        }

        let nodes: [ReviewThread]
    }

    struct CommitConnection: Codable, Hashable, Sendable {
        struct CommitNode: Codable, Hashable, Sendable {
            struct Commit: Codable, Hashable, Sendable {
                struct StatusRollup: Codable, Hashable, Sendable {
                    let state: String
                }

                let committedDate: Date?
                let statusCheckRollup: StatusRollup?
            }

            let commit: Commit
        }

        let nodes: [CommitNode]
    }

    let title: String
    let url: URL
    let number: Int
    let scope: PullRequestScope
    let author: Actor?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let headRefName: String
    let baseRefName: String
    let reviewDecision: String?
    let mergeStateStatus: String?
    let additions: Int
    let deletions: Int
    let comments: CommentConnection
    let reviewThreads: ReviewThreadConnection?
    let labels: LabelConnection
    let commits: CommitConnection
    let repository: Repository

    var id: URL { url }

    var checkState: CheckState {
        guard let value = commits.nodes.first?.commit.statusCheckRollup?.state else {
            return .none
        }
        return CheckState(rawValue: value) ?? .none
    }

    var lastPushAt: Date {
        commits.nodes.first?.commit.committedDate ?? updatedAt
    }

    var activeReviewThreads: [ReviewThreadConnection.ReviewThread] {
        guard reviewDecision == "CHANGES_REQUESTED" else { return [] }
        return reviewThreads?.nodes.filter {
            !$0.isResolved && !$0.isOutdated && !$0.comments.nodes.isEmpty
        } ?? []
    }

    var activeReviewClipboardText: String? {
        let sections = activeReviewThreads.compactMap { thread -> String? in
            guard let comment = thread.comments.nodes.first else { return nil }
            let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }

            let line = thread.line ?? thread.originalLine
            let location = line.map { "\(thread.path):\($0)" } ?? thread.path
            let author = comment.author.map { "@\($0.login)" } ?? "Unknown reviewer"
            return "\(location) — \(author)\n\(body)\n\(comment.url.absoluteString)"
        }
        guard !sections.isEmpty else { return nil }

        let feedback = sections.enumerated().map { index, section in
            "\(index + 1). \(section)"
        }.joined(separator: "\n\n")
        return """
        Review feedback for \(repository.nameWithOwner)#\(number) — \(title)
        \(url.absoluteString)

        \(feedback)
        """
    }

    var presentationStatus: PRStatus {
        if isDraft {
            return PRStatus(label: "Draft", tone: .muted, rank: 5)
        }
        if mergeStateStatus == "DIRTY" {
            return PRStatus(label: "Has conflicts", tone: .danger, rank: 0)
        }
        if reviewDecision == "CHANGES_REQUESTED" {
            return PRStatus(label: "Changes requested", tone: .danger, rank: 0)
        }
        if checkState == .failure || checkState == .error {
            return PRStatus(label: "Checks failing", tone: .danger, rank: 0)
        }
        if checkState == .pending || checkState == .expected {
            return PRStatus(label: "Checks running", tone: .info, rank: 2)
        }
        if mergeStateStatus == "BLOCKED" {
            return PRStatus(label: "Merge blocked", tone: .warning, rank: 1)
        }
        if mergeStateStatus == "BEHIND" {
            return PRStatus(label: "Branch behind", tone: .warning, rank: 1)
        }

        let mergeableStates = Set(["CLEAN", "HAS_HOOKS", "UNSTABLE"])
        if scope == .authored,
           reviewDecision == "APPROVED",
           checkState == .success,
           mergeableStates.contains(mergeStateStatus ?? "") {
            return PRStatus(label: "Ready to merge", tone: .success, rank: 3, canMerge: true)
        }
        if reviewDecision == "APPROVED" {
            return PRStatus(label: "Approved", tone: .success, rank: 3)
        }
        if reviewDecision == "REVIEW_REQUIRED" {
            return PRStatus(label: "Review needed", tone: .warning, rank: 1)
        }
        return PRStatus(label: "Open", tone: .info, rank: 2)
    }

    var group: PullRequestGroup {
        if scope == .reviewRequested {
            return .reviewRequests
        }
        if presentationStatus.tone == .danger {
            return .attention
        }
        if presentationStatus.canMerge {
            return .ready
        }
        return .waiting
    }
}

enum CheckState: String, Codable, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case error = "ERROR"
    case pending = "PENDING"
    case expected = "EXPECTED"
    case none = "NONE"
}

struct PRStatus: Hashable, Sendable {
    let label: String
    let tone: PRTone
    let rank: Int
    var canMerge = false
}

enum PullRequestGroup: Int, CaseIterable, Identifiable, Sendable {
    case attention
    case ready
    case reviewRequests
    case waiting

    var id: Self { self }

    var title: String {
        switch self {
        case .attention: "Needs attention"
        case .ready: "Ready"
        case .reviewRequests: "Review requests"
        case .waiting: "Waiting"
        }
    }
}

enum PRTone: Hashable, Sendable {
    case success
    case danger
    case warning
    case info
    case muted
}
