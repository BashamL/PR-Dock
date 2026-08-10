import AppKit
import SwiftUI

struct GitHubIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "GitHub",
            withExtension: "svg"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()
}

struct BrandIcon: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "arrow.triangle.pull")
            .font(.system(size: size * 0.43, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .background(.primary.opacity(0.07), in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    var isActive = false
    var isSpinning = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.14)
                        : Color.primary.opacity(isHovered ? 0.09 : 0),
                    in: .rect(cornerRadius: 9)
                )
                .scaleEffect(isHovered && !reduceMotion ? 1.06 : 1)
                .rotationEffect(isSpinning && !reduceMotion ? .degrees(360) : .zero)
                .animation(
                    isSpinning && !reduceMotion
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: isSpinning
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct StatusPill: View {
    let status: PRStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.tone.color)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(status.tone.color.opacity(0.11), in: .rect(cornerRadius: 7))
    }
}

extension PRTone {
    var color: Color {
        switch self {
        case .success: Color(red: 0.25, green: 0.72, blue: 0.40)
        case .danger: Color(red: 0.94, green: 0.31, blue: 0.35)
        case .warning: Color(red: 0.83, green: 0.58, blue: 0.16)
        case .info: Color.accentColor
        case .muted: Color.secondary
        }
    }
}
