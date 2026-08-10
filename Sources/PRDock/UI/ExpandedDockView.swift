import AppKit
import SwiftUI

struct ExpandedDockView: View {
    @ObservedObject var model: PRDockViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.pullRequests.isEmpty {
                summary
            }

            if let message = model.errorMessage {
                ErrorBanner(
                    message: message,
                    isStale: model.isShowingStaleData,
                    retry: model.refresh
                )
            }

            content
                .frame(maxHeight: .infinity)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandIcon(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("PR Dock")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.viewer.isEmpty ? "GitHub pull requests" : "@\(model.viewer)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            IconButton(
                systemName: "chevron.down",
                label: "Collapse PR Dock",
                action: model.collapse
            )

            IconButton(
                systemName: "arrow.clockwise",
                label: "Refresh pull requests",
                isSpinning: model.isLoading,
                action: model.refresh
            )
            .keyboardShortcut("r", modifiers: .command)

            IconButton(
                systemName: "gearshape",
                label: "Open Settings",
                action: { openSettings() }
            )

            Text(model.pullRequests.count.formatted())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .background(.primary.opacity(0.065), in: .rect(cornerRadius: 9))
                .accessibilityLabel("\(model.pullRequests.count) pull requests")
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            SummaryMetric(
                value: model.attentionCount,
                label: "attention",
                tone: .danger
            )
            Divider().frame(height: 22)
            SummaryMetric(value: model.readyCount, label: "ready", tone: .success)
            Divider().frame(height: 22)
            SummaryMetric(
                value: model.reviewRequestCount,
                label: "reviews",
                tone: .info
            )
        }
        .frame(height: 44)
        .background(.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.pullRequests.isEmpty {
            LoadingState()
        } else if model.pullRequests.isEmpty {
            EmptyState(
                setupRequired: {
                    if case .setupRequired = model.syncState { true } else { false }
                }(),
                openSettings: { openSettings() }
            )
        } else {
            pullRequestList
        }
    }

    private var pullRequestList: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(model.orderedPullRequests) { pullRequest in
                    PullRequestRow(
                        pullRequest: pullRequest,
                        isMerging: model.mergingIDs.contains(pullRequest.id),
                        open: { model.open(pullRequest) },
                        merge: { model.requestMerge(pullRequest) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.automatic)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isShowingStaleData ? PRTone.warning.color : PRTone.success.color)
                .frame(width: 6, height: 6)
            if let lastUpdated = model.lastUpdated {
                Text(model.isShowingStaleData ? "Cached" : "Synced")
                Text(lastUpdated, style: .relative)
            } else {
                Text("Waiting for first sync")
            }
            if let remaining = model.rateLimitRemaining {
                Text("· \(remaining.formatted()) API points")
            }
            Spacer()
            Button("Open GitHub", action: model.openDashboard)
                .buttonStyle(.link)
                .help("Open your pull requests on GitHub")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }
}

private struct PullRequestRow: View {
    let pullRequest: PullRequest
    let isMerging: Bool
    let open: () -> Void
    let merge: () -> Void
    @State private var isHovered = false
    @State private var isMergeHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                details
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            if pullRequest.presentationStatus.canMerge {
                Button(action: merge) {
                    Group {
                        if isMerging {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.merge")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PRTone.success.color)
                    .frame(width: 30, height: 30)
                    .background(
                        PRTone.success.color.opacity(isMergeHovered ? 0.22 : 0.11),
                        in: .rect(cornerRadius: 9)
                    )
                    .scaleEffect(isMergeHovered ? 1.06 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isMerging)
                .onHover { isMergeHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isMergeHovered)
                .help("Squash and merge #\(pullRequest.number)")
                .accessibilityLabel("Squash and merge pull request \(pullRequest.number)")
            }
        }
        .padding(10)
        .background(
            .primary.opacity(isHovered ? 0.055 : 0),
            in: .rect(cornerRadius: 13)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .contextMenu {
            Button("Open on GitHub", action: open)
            Button("Copy Branch Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    pullRequest.headRefName,
                    forType: .string
                )
            }
            if pullRequest.presentationStatus.canMerge {
                Divider()
                Button("Squash and Merge…", action: merge)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(pullRequest.repository.nameWithOwner) pull request "
            + "\(pullRequest.number), \(pullRequest.title)"
        )
        .accessibilityValue(pullRequest.presentationStatus.label)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pullRequest.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 5) {
                Text(pullRequest.repository.nameWithOwner)
                    .lineLimit(1)
                Text("· #\(pullRequest.number)")
                if pullRequest.scope == .reviewRequested {
                    Text("· review requested")
                }
                Spacer()
                Text(pullRequest.updatedAt, style: .relative)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                StatusPill(
                    status: pullRequest.presentationStatus,
                    copyText: pullRequest.activeReviewClipboardText
                )

                Label(pullRequest.headRefName, systemImage: "arrow.triangle.branch")
                    .lineLimit(1)

                if pullRequest.comments.totalCount > 0 {
                    Label(
                        pullRequest.comments.totalCount.formatted(),
                        systemImage: "bubble.left"
                    )
                }

                Spacer(minLength: 0)
                Text("+\(pullRequest.additions)")
                    .foregroundStyle(PRTone.success.color)
                Text("−\(pullRequest.deletions)")
                    .foregroundStyle(PRTone.danger.color)
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var statusIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(
                systemName: pullRequest.scope == .reviewRequested
                    ? "person.crop.circle.badge.questionmark"
                    : "arrow.triangle.pull"
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(pullRequest.presentationStatus.tone.color)
            .frame(width: 28, height: 28)
            .background(
                pullRequest.presentationStatus.tone.color.opacity(0.11),
                in: .rect(cornerRadius: 9)
            )

            if pullRequest.checkState != .none {
                Circle()
                    .fill(checkColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.background.opacity(0.8), lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }

    private var checkColor: Color {
        switch pullRequest.checkState {
        case .success: PRTone.success.color
        case .failure, .error: PRTone.danger.color
        case .pending, .expected: PRTone.warning.color
        case .none: .clear
        }
    }
}

private struct SummaryMetric: View {
    let value: Int
    let label: String
    let tone: PRTone

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.color).frame(width: 6, height: 6)
            Text(value.formatted()).fontWeight(.semibold)
            Text(label).foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorBanner: View {
    let message: String
    let isStale: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : "exclamationmark.circle")
            Text(message)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .buttonStyle(.link)
                .fontWeight(.semibold)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(isStale ? PRTone.warning.color : PRTone.danger.color)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(
            (isStale ? PRTone.warning.color : PRTone.danger.color).opacity(0.09)
        )
    }
}

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading pull requests…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyState: View {
    let setupRequired: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(
                systemName: setupRequired
                    ? "wrench.and.screwdriver"
                    : "checkmark.circle"
            )
            .font(.system(size: 27, weight: .light))
            .foregroundStyle(.secondary)

            Text(setupRequired ? "Finish GitHub setup" : "Everything is clear")
                .font(.system(size: 13, weight: .semibold))

            Text(
                setupRequired
                    ? "Install and authenticate GitHub CLI, then refresh."
                    : "No pull requests match your current scopes."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if setupRequired {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
