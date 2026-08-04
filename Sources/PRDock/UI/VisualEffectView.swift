import SwiftUI

struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.17, blue: 0.20),
                                Color(red: 0.075, green: 0.08, blue: 0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.38), radius: 28, y: 16)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
