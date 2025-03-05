import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(colorScheme == .dark ? 
                Color.white.opacity(isEnabled ? 0.85 : 0.5) : 
                Color.primary.opacity(isEnabled ? 0.75 : 0.4))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    // Glass effect background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(configuration.isPressed ? 0.08 : (isEnabled ? 0.06 : 0.03))
                                : Color.black.opacity(configuration.isPressed ? 0.06 : (isEnabled ? 0.04 : 0.02))
                        )
                        .overlay(
                            // Add a subtle gradient overlay
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .opacity(isEnabled ? 1 : 0.5)
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(isEnabled ? (configuration.isPressed ? 0.1 : 0.08) : 0.05)
                            : Color.black.opacity(isEnabled ? (configuration.isPressed ? 0.08 : 0.06) : 0.03),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

// A modern, minimal secondary button style
struct MinimalButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(colorScheme == .dark ?
                Color.white.opacity(isEnabled ? 0.85 : 0.5) :
                Color.primary.opacity(isEnabled ? 0.75 : 0.4))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(isEnabled ? (configuration.isPressed ? 0.1 : 0.08) : 0.05)
                            : Color.black.opacity(isEnabled ? (configuration.isPressed ? 0.08 : 0.06) : 0.03),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}
