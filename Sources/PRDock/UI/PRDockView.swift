import SwiftUI

struct PRDockRootView: View {
    @ObservedObject var model: PRDockViewModel

    var body: some View {
        Group {
            if model.showsExpandedContent {
                ExpandedDockView(model: model)
            } else {
                CollapsedDockView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(model.isContentVisible ? 1 : 0)
        .scaleEffect(
            model.isContentVisible
                ? 1
                : (model.showsExpandedContent ? 0.99 : 0.96),
            anchor: .bottom
        )
        .offset(y: model.isContentVisible ? 0 : 4)
        .animation(
            .timingCurve(0.2, 0.9, 0.2, 1, duration: 0.09),
            value: model.isContentVisible
        )
    }
}

private struct CollapsedDockView: View {
    @ObservedObject var model: PRDockViewModel

    var body: some View {
        HStack(spacing: 7) {
            Button(action: model.togglePinned) {
                BrandIcon(size: 34)
            }
            .buttonStyle(.plain)
            .help("Open PR Dock")

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 26)

            HStack(spacing: 5) {
                if model.isLoading && model.pullRequests.isEmpty {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else if model.recentPullRequests.isEmpty {
                    Text("No open pull requests")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(model.recentPullRequests) { pullRequest in
                        MiniPullRequestButton(
                            pullRequest: pullRequest,
                            action: { model.open(pullRequest) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)

            let remainder = model.pullRequests.count - model.recentPullRequests.count
            if remainder > 0 {
                Text("+\(remainder)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.up.2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
        .padding(.horizontal, 9)
        .frame(width: 268, height: 56)
        .glassCard(cornerRadius: 18)
    }
}

private struct MiniPullRequestButton: View {
    let pullRequest: PullRequest
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.065))

                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isHovered ? 0.95 : 0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Circle()
                    .fill(pullRequest.presentationStatus.tone.color)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                    .padding(3)
            }
            .frame(width: 32, height: 32)
            .scaleEffect(isHovered ? 1.12 : 1)
            .offset(y: isHovered ? -3 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .help("\(pullRequest.repository.nameWithOwner) #\(pullRequest.number) · \(pullRequest.title)")
    }
}

private struct ExpandedDockView: View {
    @ObservedObject var model: PRDockViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.pullRequests.isEmpty {
                metrics
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error)
            }

            Group {
                if model.isLoading && model.pullRequests.isEmpty {
                    loadingState
                } else if model.pullRequests.isEmpty {
                    emptyState
                } else {
                    pullRequestList
                }
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 20)
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandIcon(size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pull request cockpit")
                    .font(.system(size: 13.5, weight: .semibold))
                Text(model.viewer.isEmpty ? "GitHub" : "github.com/\(model.viewer)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HeaderButton(
                systemName: model.isPinned ? "pin.slash" : "pin",
                help: model.isPinned ? "Unpin" : "Keep expanded",
                isActive: model.isPinned,
                action: model.togglePinned
            )

            HeaderButton(
                systemName: "arrow.clockwise",
                help: "Refresh now",
                isSpinning: model.isLoading,
                action: model.refresh
            )

            Text("\(model.pullRequests.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 25, minHeight: 25)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 17)
        .frame(height: 58)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            MetricView(value: model.readyCount, label: "ready", tone: .success)
            Divider().opacity(0.25)
            MetricView(value: model.attentionCount, label: "attention", tone: .danger)
            Divider().opacity(0.25)
            MetricView(value: model.draftCount, label: "drafts", tone: .muted)
        }
        .frame(height: 42)
        .background(Color.black.opacity(0.13))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.25)
        }
    }

    private var pullRequestList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.orderedPullRequests) { pullRequest in
                    PullRequestRow(
                        pullRequest: pullRequest,
                        isMerging: model.mergingIDs.contains(pullRequest.id),
                        open: { model.open(pullRequest) },
                        merge: { model.merge(pullRequest) }
                    )
                }
            }
            .padding(7)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Loading pull requests…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.secondary)
            Text("Everything is merged")
                .font(.system(size: 12.5, weight: .semibold))
            Text("No open pull requests. Nice work.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(PRTone.success.color)
                .frame(width: 5, height: 5)
                .shadow(color: PRTone.success.color.opacity(0.7), radius: 3)
            Text("Syncs every minute")
            if let remaining = model.rateLimitRemaining {
                Text("· \(remaining.formatted()) API points")
            }
            Spacer()
            Button("Open GitHub ↗", action: model.openDashboard)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .overlay(alignment: .top) {
            Divider().opacity(0.3)
        }
    }
}

private struct PullRequestRow: View {
    let pullRequest: PullRequest
    let isMerging: Bool
    let open: () -> Void
    let merge: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 11) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 5) {
                        Text(pullRequest.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 5) {
                            Text(pullRequest.repository.nameWithOwner)
                                .lineLimit(1)
                            Text("·")
                            Text("#\(pullRequest.number)")
                            Spacer()
                            Text(pullRequest.updatedAt, style: .relative)
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)

                        HStack(spacing: 5) {
                            StatusPill(status: pullRequest.presentationStatus)

                            Label(pullRequest.headRefName, systemImage: "arrow.triangle.branch")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))

                            Text("+\(pullRequest.additions)")
                                .foregroundStyle(PRTone.success.color)
                            Text("−\(pullRequest.deletions)")
                                .foregroundStyle(PRTone.danger.color)
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if pullRequest.presentationStatus.canMerge {
                Button(action: merge) {
                    Group {
                        if isMerging {
                            Image(systemName: "ellipsis")
                        } else {
                            Image(systemName: "arrow.triangle.merge")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PRTone.success.color)
                    .frame(width: 30, height: 30)
                    .background(PRTone.success.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(PRTone.success.color.opacity(0.2), lineWidth: 0.75)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isMerging)
                .help("Squash and merge #\(pullRequest.number)")
            }
        }
        .padding(10)
        .background(Color.white.opacity(isHovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var statusIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(pullRequest.presentationStatus.tone.color)
                .frame(width: 25, height: 25)
                .background(
                    pullRequest.presentationStatus.tone.color.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            if pullRequest.checkState != .none {
                Circle()
                    .fill(checkColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
            }
        }
    }

    private var checkColor: Color {
        switch pullRequest.checkState {
        case .success: return PRTone.success.color
        case .failure, .error: return PRTone.danger.color
        case .pending, .expected: return PRTone.warning.color
        case .none: return .clear
        }
    }
}

private struct BrandIcon: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .font(.system(size: size * 0.43, weight: .semibold))
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.3))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.75)
            }
    }
}

private struct HeaderButton: View {
    let systemName: String
    let help: String
    var isActive = false
    var isSpinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? PRTone.info.color : Color.secondary)
                .frame(width: 25, height: 25)
                .background(
                    isActive ? PRTone.info.color.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .rotationEffect(isSpinning ? .degrees(360) : .zero)
                .animation(
                    isSpinning
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: isSpinning
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MetricView: View {
    let value: Int
    let label: String
    let tone: PRTone

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
                .shadow(color: tone.color.opacity(0.65), radius: 3)
            Text("\(value)")
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5))
        .frame(maxWidth: .infinity)
    }
}

private struct StatusPill: View {
    let status: PRStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(status.tone.color)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(status.tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.circle")
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(PRTone.danger.color)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(PRTone.danger.color.opacity(0.08))
    }
}
