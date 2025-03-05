import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .primary.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Glass effect background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(configuration.isPressed ? 0.07 : 0.05)
                                : Color.black.opacity(configuration.isPressed ? 0.05 : 0.03)
                        )
                    
                    // Subtle pattern overlay for texture
                    if colorScheme == .dark {
                        Image(systemName: "circle.grid.2x2")
                            .resizable(resizingMode: .tile)
                            .foregroundColor(.white)
                            .opacity(0.02)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.1)
                            : Color.black.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
