import SwiftUI

/// A primary button style with a blue background and white text
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Base gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            isEnabled ? Color.blue : Color.gray,
                            isEnabled ? Color.blue.opacity(0.8) : Color.gray.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Hover/press effect
                    if configuration.isPressed {
                        Color.white.opacity(0.1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isEnabled 
                            ? Color.white.opacity(colorScheme == .dark ? 0.1 : 0.2)
                            : Color.gray.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .shadow(color: isEnabled ? Color.blue.opacity(0.3) : Color.clear, radius: 5, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

/// A secondary button style with a subtle background
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isEnabled ? (colorScheme == .dark ? .white : .primary) : .gray)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark 
                          ? Color.white.opacity(configuration.isPressed ? 0.07 : 0.05)
                          : Color.black.opacity(configuration.isPressed ? 0.07 : 0.05))
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
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

/// A destructive button style with a red background
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Base gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            isEnabled ? Color.red : Color.gray,
                            isEnabled ? Color.red.opacity(0.8) : Color.gray.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Hover/press effect
                    if configuration.isPressed {
                        Color.white.opacity(0.1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isEnabled 
                            ? Color.white.opacity(colorScheme == .dark ? 0.1 : 0.2)
                            : Color.gray.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .shadow(color: isEnabled ? Color.red.opacity(0.3) : Color.clear, radius: 5, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
} 