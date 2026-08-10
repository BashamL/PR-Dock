import SwiftUI

struct CollapsedDockView: View {
    @ObservedObject var model: PRDockViewModel

    var body: some View {
        Button(action: model.expand) {
            HStack(spacing: 10) {
                BrandIcon(size: 36)

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Label(primarySummary.text, systemImage: primarySummary.icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(primarySummary.color)
                        .lineLimit(1)

                    secondarySummary
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open PR Dock")
        .accessibilityLabel("Open PR Dock")
        .accessibilityValue(accessibilitySummary)
    }

    private var primarySummary: (text: String, icon: String, color: Color) {
        if model.isLoading && model.pullRequests.isEmpty {
            return ("Refreshing pull requests", "arrow.clockwise", .secondary)
        }
        if case .setupRequired = model.syncState {
            return ("GitHub setup needed", "wrench.and.screwdriver", PRTone.warning.color)
        }
        if case .failed = model.syncState {
            return ("Couldn’t refresh GitHub", "exclamationmark.triangle.fill", PRTone.danger.color)
        }
        if model.attentionCount > 0 {
            return (
                "\(model.attentionCount) need attention",
                "exclamationmark.triangle.fill",
                PRTone.danger.color
            )
        }
        if model.readyCount > 0 {
            return (
                "\(model.readyCount) ready to merge",
                "arrow.triangle.merge",
                PRTone.success.color
            )
        }
        if model.reviewRequestCount > 0 {
            let label = model.reviewRequestCount == 1
                ? "1 review waiting"
                : "\(model.reviewRequestCount) reviews waiting"
            return (label, "person.crop.circle.badge.questionmark", PRTone.info.color)
        }
        if model.waitingCount > 0 {
            return (
                "\(model.waitingCount) waiting",
                "clock",
                .secondary
            )
        }
        return ("Everything is clear", "checkmark.circle", PRTone.success.color)
    }

    @ViewBuilder
    private var secondarySummary: some View {
        if model.isShowingStaleData {
            Text("Cached data · refresh failed")
        } else if model.isLoading {
            Text("Refreshing \(model.pullRequests.count) open")
        } else if model.lastUpdated != nil {
            Text("\(model.pullRequests.count) open · synced")
        } else {
            Text("\(model.pullRequests.count) open")
        }
    }

    private var accessibilitySummary: String {
        "\(primarySummary.text). \(model.pullRequests.count) open pull requests."
    }
}
