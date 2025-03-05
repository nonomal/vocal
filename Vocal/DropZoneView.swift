// DropZoneView.swift
import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let onTap: () -> Void
    var onPaste: ((String) -> Void)?
    
    @State private var isHovering = false
    @State private var isPulsing = false
    @Environment(\.colorScheme) private var colorScheme
    
    private let accentGradient = LinearGradient(
        colors: [Color.blue, Color.purple.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 32) {
                // Icon with animation
                ZStack {
                    // Background circles
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 90, height: 90)
                        .scaleEffect(isPulsing ? 1.1 : 1.0)
                    
                    Circle()
                        .fill(
                            isDragging ? accentGradient : LinearGradient(
                                gradient: Gradient(colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.2)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: isDragging ? 2 : 1)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isDragging ? "arrow.down.doc.fill" : "arrow.down.doc")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.accentColor)
                        .opacity(isDragging ? 1.0 : 0.8)
                }
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                .onAppear {
                    // Start subtle pulsing animation
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                
                // Text content
                VStack(spacing: 16) {
                    // Main text
                    Text("Drop a video file or click to browse")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    // Paste hint with keyboard shortcut styling
                    VStack(spacing: 8) {
                        Text("Or paste a YouTube URL")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        KeyboardShortcut(keys: ["⌘", "V"])
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            colorScheme == .dark ? 
                                Color.black.opacity(0.3) : 
                                Color.white.opacity(0.95)
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            isDragging ? 
                                LinearGradient(
                                    colors: [Color.blue, Color.purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color.primary.opacity(isHovering ? 0.2 : 0.1),
                                        Color.primary.opacity(isHovering ? 0.1 : 0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: isDragging ? 2 : 1
                        )
                    
                    // Subtle patterns for visual interest (only in light mode)
                    if colorScheme == .light {
                        Circle()
                            .fill(Color.blue.opacity(0.03))
                            .frame(width: 200, height: 200)
                            .offset(x: -100, y: -100)
                        
                        Circle()
                            .fill(Color.purple.opacity(0.03))
                            .frame(width: 200, height: 200)
                            .offset(x: 100, y: 100)
                    }
                }
            )
            .overlay(
                // Add a subtle glow when dragging
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.accentColor.opacity(isDragging ? 0.3 : 0), lineWidth: 3)
                    .blur(radius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering && !isDragging ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
    }
}

// MARK: - Supporting Views

struct KeyboardShortcut: View {
    let keys: [String]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            }
        }
    }
}

// MARK: - Preview

struct DropZoneView_Previews: PreviewProvider {
    static var previews: some View {
        DropZoneView(isDragging: .constant(false), onTap: {})
            .frame(width: 500, height: 400)
            .padding()
            .previewLayout(.sizeThatFits)
        
        DropZoneView(isDragging: .constant(true), onTap: {})
            .frame(width: 500, height: 400)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
