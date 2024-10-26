// DropZoneView.swift
import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let onTap: () -> Void
    var onPaste: ((String) -> Void)?
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 15) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text("Click or drop a video here")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                // Paste hint
                Text("⌘V to paste YouTube URL")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [10]))
                    .background(Color.clear)
            )
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            isDragging ?
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding()
            : nil
        )
    }
}
