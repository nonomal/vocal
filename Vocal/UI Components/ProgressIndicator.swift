import SwiftUI

struct ProgressIndicator: View {
    let progress: Double
    let message: String
    let detail: String?
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(VocalTheme.Colors.divider, lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [VocalTheme.Colors.accent, VocalTheme.Colors.accent.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(progress * 100))%")
                    .font(VocalTheme.Typography.headline)
            }
            
            Text(message)
                .font(VocalTheme.Typography.body)
                .foregroundColor(.secondary)
            
            if let detail = detail {
                Text(detail)
                    .font(VocalTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: 300)
        .padding(VocalTheme.padding)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(VocalTheme.Colors.surface)
                .shadow(color: .black.opacity(0.1), radius: 20)
        )
    }
}

#Preview {
    ProgressIndicator(
        progress: 0.65,
        message: "Downloading...",
        detail: "2.5 MB/s"
    )
} 