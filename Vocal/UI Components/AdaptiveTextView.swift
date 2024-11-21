import SwiftUI

struct AdaptiveTextView: View {
    let text: String
    let maxSize: CGFloat = 24
    let minSize: CGFloat = 14
    
    @State private var fontSize: CGFloat = 24
    @State private var frameSize: CGSize = .zero
    
    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SizePreferenceKey.self,
                        value: geometry.size
                    )
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { size in
                frameSize = size
                adjustFontSize()
            }
    }
    
    private func adjustFontSize() {
        let textLength = text.count
        let availableArea = frameSize.width * frameSize.height
        
        // Calculate ideal font size based on text length and available area
        let calculatedSize = sqrt(availableArea / CGFloat(textLength)) * 0.8
        fontSize = min(max(calculatedSize, minSize), maxSize)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
} 