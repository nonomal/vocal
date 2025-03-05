import SwiftUI

/// A row displaying a dependency and its installation options
struct DependencyRow: View {
    let name: String
    let installCommand: String
    let helpURL: URL?
    let isEmbeddable: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(name)
                    .font(.headline)
                
                Spacer()
                
                if isEmbeddable {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        
                        Text("Auto-Setup")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.1))
                    )
                }
            }
            
            HStack {
                Text("Terminal command:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(installCommand, forType: .string)
                }) {
                    HStack(spacing: 2) {
                        Text("Copy")
                            .font(.caption2)
                        
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
            
            Text(installCommand)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            
            if let helpURL = helpURL {
                Link(destination: helpURL) {
                    Text("Learn more")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: Color.primary.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}