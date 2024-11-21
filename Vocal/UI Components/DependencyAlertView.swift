import SwiftUI

struct DependencyAlertView: View {
    let missingDependencies: [DependencyStatus]
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                
                Text("Missing Dependencies")
                    .font(.title2.bold())
                
                Text("Some required components are not installed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Dependencies list
            VStack(alignment: .leading, spacing: 16) {
                ForEach(missingDependencies, id: \.dependency.rawValue) { status in
                    if case .missing(let dep, let cmd, let url) = status.type {
                        DependencyRow(
                            name: dep.rawValue,
                            installCommand: cmd,
                            helpURL: url
                        )
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            
            // Buttons
            HStack(spacing: 12) {
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                .buttonStyle(GlassButtonStyle())
                
                Button("Install Homebrew") {
                    if let url = URL(string: "https://brew.sh") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(GlassButtonStyle())
                
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(GlassButtonStyle())
            }
            
            // Help text
            Text("You can install these dependencies using Homebrew or manually from their websites")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(30)
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(radius: 20)
        )
    }
}

struct DependencyRow: View {
    let name: String
    let installCommand: String
    let helpURL: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            
            HStack {
                Text(installCommand)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(6)
                
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installCommand, forType: .string)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            
            Button("Installation Guide →") {
                if let url = URL(string: helpURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
    }
}
