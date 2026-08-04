import Foundation
import SwiftUI

struct GitHubPayload: Decodable {
    let viewer: String
    let rateLimit: RateLimit?
    let prs: [PullRequest]
}

struct RateLimit: Decodable {
    let remaining: Int
    let resetAt: Date?
}

struct PullRequest: Decodable, Identifiable, Hashable {
    struct Repository: Decodable, Hashable {
        let nameWithOwner: String
    }

    struct LabelConnection: Decodable, Hashable {
        struct Label: Decodable, Hashable {
            let name: String
            let color: String
        }

        let nodes: [Label]
    }

    struct CommentConnection: Decodable, Hashable {
        let totalCount: Int
    }

    struct CommitConnection: Decodable, Hashable {
        struct CommitNode: Decodable, Hashable {
            struct Commit: Decodable, Hashable {
                struct StatusRollup: Decodable, Hashable {
                    let state: String
                }

                let statusCheckRollup: StatusRollup?
            }

            let commit: Commit
        }

        let nodes: [CommitNode]
    }

    let title: String
    let url: URL
    let number: Int
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
        if mergeStateStatus == "BLOCKED" {
            return PRStatus(label: "Merge blocked", tone: .warning, rank: 1)
        }
        if mergeStateStatus == "BEHIND" {
            return PRStatus(label: "Branch behind", tone: .warning, rank: 1)
        }

        let mergeableStates = Set(["CLEAN", "HAS_HOOKS", "UNSTABLE"])
        if reviewDecision == "APPROVED",
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
        if checkState == .pending || checkState == .expected {
            return PRStatus(label: "Checks running", tone: .info, rank: 2)
        }
        return PRStatus(label: "Open", tone: .info, rank: 2)
    }
}

enum CheckState: String {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case error = "ERROR"
    case pending = "PENDING"
    case expected = "EXPECTED"
    case none = "NONE"
}

struct PRStatus: Hashable {
    let label: String
    let tone: PRTone
    let rank: Int
    var canMerge = false
}

enum PRTone: Hashable {
    case success
    case danger
    case warning
    case info
    case muted

    var color: Color {
        switch self {
        case .success: return Color(red: 0.29, green: 0.82, blue: 0.48)
        case .danger: return Color(red: 1.0, green: 0.42, blue: 0.45)
        case .warning: return Color(red: 0.91, green: 0.70, blue: 0.32)
        case .info: return Color(red: 0.40, green: 0.67, blue: 0.98)
        case .muted: return Color(red: 0.58, green: 0.61, blue: 0.66)
        }
    }
}
