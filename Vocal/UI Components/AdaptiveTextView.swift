import SwiftUI

/// A modern text view that adapts its presentation based on content
struct AdaptiveTextView: View {
    let text: String
    
    @State private var fontSize: CGFloat = 16
    @State private var isTextHovered = false
    @State private var hoveredParagraphIndex: Int? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.7))
                .ignoresSafeArea()
            
            if text.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Content
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        headerView
                        
                        // Paragraphs
                        contentView
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            // Empty state icon with gradient
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [
                            Color.blue.opacity(0.03),
                            Color.purple.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "text.bubble")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(Color.primary.opacity(0.5))
            }
            
            Text("No transcription yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
            
            Text("Drop a video file or paste a YouTube URL")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerView: some View {
        HStack {
            // Title
            Text("Transcription")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundColor(.primary.opacity(0.9))
            
            Spacer()
            
            // Control buttons - font size adjustment
            HStack(spacing: 12) {
                Button(action: { 
                    if fontSize > 14 {
                        withAnimation { fontSize -= 1 }
                    }
                }) {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { 
                    if fontSize < 20 {
                        withAnimation { fontSize += 1 }
                    }
                }) {
                    Image(systemName: "textformat.size.larger")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .frame(height: 12)
                    .opacity(0.5)
                
                // Stats
                StatView(
                    icon: "text.word.count",
                    value: "\(wordCount)",
                    label: "words"
                )
                
                StatView(
                    icon: "clock",
                    value: formattedReadingTime,
                    label: "read time"
                )
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }
    
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<paragraphs.count, id: \.self) { index in
                HStack(alignment: .top, spacing: 0) {
                    // Paragraph text
                    Text(paragraphs[index])
                        .font(.system(size: fontSize, weight: .regular, design: .default))
                        .lineSpacing(6)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? 
                             Color(white: hoveredParagraphIndex == index ? 0.17 : 0.15) : 
                             (hoveredParagraphIndex == index ? Color.white : Color.white.opacity(0.9)))
                        .shadow(
                            color: colorScheme == .dark ? 
                                Color.black.opacity(0.25) : 
                                Color.black.opacity(hoveredParagraphIndex == index ? 0.07 : 0.05),
                            radius: hoveredParagraphIndex == index ? 6 : 4,
                            x: 0,
                            y: hoveredParagraphIndex == index ? 2 : 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            colorScheme == .dark ? 
                                Color.white.opacity(hoveredParagraphIndex == index ? 0.1 : 0.05) : 
                                Color.black.opacity(hoveredParagraphIndex == index ? 0.05 : 0.03),
                            lineWidth: 0.5
                        )
                )
                .padding(.horizontal, 16)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if hovering {
                            hoveredParagraphIndex = index
                        } else if hoveredParagraphIndex == index {
                            hoveredParagraphIndex = nil
                        }
                    }
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hoveredParagraphIndex == index)
            }
            
            // Add some bottom padding
            Color.clear.frame(height: 20)
        }
    }
    
    // MARK: - Helper Methods
    
    private var paragraphs: [String] {
        // Split text into paragraphs, filtering out empty ones
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    private var formattedReadingTime: String {
        let minutes = Double(wordCount) / 200.0 // Average reading speed
        if minutes < 1 {
            return "<1m"
        } else if minutes < 60 {
            return "\(Int(ceil(minutes)))m"
        } else {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)h \(mins)m"
        }
    }
}

/// A clean stat view for word count and reading time
struct StatView: View {
    let icon: String
    let value: String
    let label: String
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? 
                    Color.white.opacity(isHovered ? 0.07 : 0.05) : 
                    Color.black.opacity(isHovered ? 0.05 : 0.03))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
} 