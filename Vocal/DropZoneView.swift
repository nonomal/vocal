// DropZoneView.swift
import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let onTap: () -> Void
    var onPaste: ((String) -> Void)?
    
    @State private var isHovering = false
    @State private var isPulsing = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Updated gradient with more subtle colors
    private let accentGradient = LinearGradient(
        colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 24) {
                // Icon with subtle animation
                ZStack {
                    // Animated ring
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(isDragging ? 0.5 : 0.2),
                                    Color.purple.opacity(isDragging ? 0.4 : 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDragging ? 2 : 1.5
                        )
                        .frame(width: 84, height: 84)
                        .scaleEffect(isPulsing ? 1.05 : 1.0)
                    
                    // Inner circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(isDragging ? 0.12 : 0.08),
                                    Color.purple.opacity(isDragging ? 0.10 : 0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                    
                    // Icon
                    Image(systemName: isDragging ? "arrow.down.doc.fill" : "arrow.down.doc")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(
                            Color.blue.opacity(isDragging ? 0.9 : 0.7)
                        )
                }
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                .onAppear {
                    // Start subtle pulsing animation
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                
                // Text content
                VStack(spacing: 12) {
                    // Main text
                    Text("Drop video file or click to browse")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    // Paste hint with keyboard shortcut styling
                    HStack(spacing: 6) {
                        Text("Paste YouTube URL")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        Text("⌘V")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .opacity(0.8)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    // Base background - more refined with less opacity
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            colorScheme == .dark ? 
                                Color.black.opacity(0.2) : 
                                Color.white.opacity(0.7)
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isDragging ? 
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color.primary.opacity(isHovering ? 0.1 : 0.07),
                                        Color.primary.opacity(isHovering ? 0.07 : 0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: isDragging ? 1.5 : 1
                        )
                    
                    // Subtle background elements - more minimal
                    if colorScheme == .light {
                        Circle()
                            .fill(Color.blue.opacity(0.02))
                            .frame(width: 200, height: 200)
                            .offset(x: -100, y: -100)
                        
                        Circle()
                            .fill(Color.purple.opacity(0.02))
                            .frame(width: 200, height: 200)
                            .offset(x: 100, y: 100)
                    }
                }
            )
            .overlay(
                // Add a subtle glow when dragging - more refined
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(isDragging ? 0.2 : 0),
                                Color.purple.opacity(isDragging ? 0.15 : 0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
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
        .scaleEffect(isHovering && !isDragging ? 1.005 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
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
