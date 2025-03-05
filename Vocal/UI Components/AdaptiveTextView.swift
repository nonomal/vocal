import SwiftUI

/// A modern text view that adapts its presentation based on content
struct AdaptiveTextView: View {
    let text: String
    
    @State private var fontSize: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.9))
                .ignoresSafeArea()
            
            if text.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Content
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        headerView
                        
                        // Paragraphs
                        contentView
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "text.bubble")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No transcription available")
                .font(.title3.weight(.medium))
                .foregroundColor(.gray)
            
            Text("Drop a video file or paste a YouTube URL to get started")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerView: some View {
        HStack {
            Text("Transcription")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            // Stats
            HStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<paragraphs.count, id: \.self) { index in
                Text(paragraphs[index])
                    .font(.system(size: fontSize, weight: .regular, design: .serif))
                    .lineSpacing(6)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                            .shadow(
                                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                                radius: 5,
                                x: 0,
                                y: 2
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05),
                                lineWidth: 0.5
                            )
                    )
                    .padding(.horizontal, 16)
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
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.9))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
    }
} 