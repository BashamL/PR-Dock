import SwiftUI

struct CollapsedDockView: View {
    @ObservedObject var model: PRDockViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: model.expand) {
            HStack(spacing: 8) {
                GitHubIcon(size: 22)
                    .scaleEffect(isHovered && !reduceMotion ? 1.06 : 1)

                Divider()
                    .frame(height: 34)

                Group {
                    if let pullRequest = model.latestAuthoredPullRequest {
                        PullRequestPreview(
                            pullRequest: pullRequest,
                            isStale: model.isShowingStaleData
                        )
                    } else {
                        compactMessage
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                .primary.opacity(isHovered ? 0.035 : 0),
                in: .rect(cornerRadius: 20)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help("Open PR Dock")
        .accessibilityLabel("Open PR Dock")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let pullRequest = model.latestAuthoredPullRequest else {
            return compactMessageValue.title
        }
        return "Latest owned pull request: \(pullRequest.title). "
            + "\(pullRequest.presentationStatus.label). \(ciSummary(for: pullRequest).text)."
    }

    private var compactMessageValue: (
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) {
        if model.isLoading && model.pullRequests.isEmpty {
            return (
                "Refreshing pull requests",
                "Checking GitHub",
                "arrow.clockwise",
                .secondary
            )
        }
        if case .setupRequired = model.syncState {
            return (
                "GitHub setup needed",
                "Open PR Dock to configure",
                "wrench.and.screwdriver",
                PRTone.warning.color
            )
        }
        if case .failed = model.syncState {
            return (
                "Couldn’t refresh GitHub",
                "Open PR Dock to retry",
                "exclamationmark.triangle.fill",
                PRTone.danger.color
            )
        }
        if model.reviewRequestCount > 0 {
            let reviews = model.reviewRequestCount == 1
                ? "1 review request waiting"
                : "\(model.reviewRequestCount) review requests waiting"
            return (
                "No owned pull requests",
                reviews,
                "person.crop.circle.badge.questionmark",
                PRTone.info.color
            )
        }
        return (
            "No owned pull requests",
            "Everything is clear",
            "checkmark.circle",
            PRTone.success.color
        )
    }

    private var compactMessage: some View {
        let message = compactMessageValue
        return HStack(spacing: 8) {
            Image(systemName: message.icon)
                .foregroundStyle(message.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message.subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
        }
    }
}

private struct PullRequestPreview: View {
    let pullRequest: PullRequest
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pullRequest.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(pullRequest.repository.nameWithOwner)
                    .lineLimit(1)
                Text("#\(pullRequest.number)")
                Text("·")
                Text(pullRequest.headRefName)
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                InlineStatus(
                    icon: nil,
                    text: pullRequest.presentationStatus.label,
                    color: pullRequest.presentationStatus.tone.color
                )

                let ci = ciSummary(for: pullRequest)
                InlineStatus(icon: ci.icon, text: ci.text, color: ci.color)

                if isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(PRTone.warning.color)
                        .help("Showing cached data")
                }
            }
        }
    }
}

private struct InlineStatus: View {
    let icon: String?
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(color)
    }
}

private func ciSummary(
    for pullRequest: PullRequest
) -> (text: String, icon: String, color: Color) {
    switch pullRequest.checkState {
    case .success:
        ("CI passed", "checkmark.circle.fill", PRTone.success.color)
    case .failure, .error:
        ("CI failed", "xmark.circle.fill", PRTone.danger.color)
    case .pending, .expected:
        ("CI running", "clock.fill", PRTone.warning.color)
    case .none:
        ("No CI", "minus.circle", Color.secondary)
    }
}
