import SwiftUI

struct PRDockRootView: View {
    @ObservedObject var model: PRDockViewModel
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            Group {
                if model.isExpanded {
                    ExpandedDockView(model: model)
                } else {
                    CollapsedDockView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: model.isExpanded ? 24 : 20)
            )
            .glassEffectID("pr-dock-surface", in: glassNamespace)
            .contentShape(.rect(cornerRadius: model.isExpanded ? 24 : 20))
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.04),
            value: model.presentation
        )
        .confirmationDialog(
            mergeTitle,
            isPresented: Binding(
                get: { model.pendingMerge != nil },
                set: { if !$0 { model.cancelMerge() } }
            ),
            presenting: model.pendingMerge
        ) { _ in
            Button("Squash and Merge", role: .destructive) {
                model.confirmMerge()
            }
            Button("Cancel", role: .cancel) {
                model.cancelMerge()
            }
        } message: { pullRequest in
            Text(
                "\(pullRequest.repository.nameWithOwner) #\(pullRequest.number)\n\n"
                + "PR Dock will refresh its status, then merge it immediately."
            )
        }
    }

    private var mergeTitle: String {
        guard let pullRequest = model.pendingMerge else {
            return "Squash and merge?"
        }
        return "Squash and merge #\(pullRequest.number)?"
    }
}
