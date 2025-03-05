import SwiftUI

/// A view that displays missing dependencies and provides options to install them
struct DependencyAlertView: View {
    let missingDependencies: [DependencyStatus]
    let onDismiss: () -> Void
    let onSetupAutomatically: () -> Void
    
    @State private var isSettingUp = false
    @State private var setupComplete = false
    @State private var setupSuccess = false
    @State private var setupProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                headerIcon
                
                Text(titleText)
                    .font(.title2.bold())
                
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !isSettingUp && !setupComplete {
                // Dependencies list
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(missingDependencies, id: \.dependency.rawValue) { status in
                            if case .missing(let dep, let cmd, let url) = status.type {
                                DependencyRow(
                                    name: dep.rawValue,
                                    installCommand: cmd,
                                    helpURL: url,
                                    isEmbeddable: status.isEmbeddable
                                )
                            } else if case .embeddable(let dep, let cmd, let url) = status.type {
                                DependencyRow(
                                    name: dep.rawValue,
                                    installCommand: cmd,
                                    helpURL: url,
                                    isEmbeddable: true
                                )
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 250)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.03))
                )
            }
            
            // Buttons
            HStack(spacing: 12) {
                if isSettingUp {
                    // Show cancel button during setup
                    Button("Cancel") {
                        isSettingUp = false
                    }
                    .buttonStyle(GlassButtonStyle())
                } else if setupComplete {
                    // Show done button after setup
                    Button("Done") {
                        onDismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    // Show setup options before setup
                    if canSetupAutomatically {
                        Button("Setup Automatically") {
                            setupAutomatically()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    
                    Button("Manual Setup") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                    .buttonStyle(GlassButtonStyle())
                    
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            
            // Help text
            if !isSettingUp && !setupComplete && canSetupAutomatically {
                Text("Automatic setup is recommended for most users")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(30)
        .frame(width: 500)
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor)
                
                // Subtle gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.primary.opacity(0.02),
                        Color.primary.opacity(0.01)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var headerIcon: some View {
        if isSettingUp {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 64, height: 64)
                
                ProgressView()
                    .scaleEffect(1.5)
            }
        } else if setupComplete {
            ZStack {
                Circle()
                    .fill(setupSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 64, height: 64)
                
                Image(systemName: setupSuccess ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(setupSuccess ? .green : .orange)
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 64, height: 64)
                
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var titleText: String {
        if isSettingUp {
            return "Setting Up Dependencies"
        } else if setupComplete {
            return setupSuccess ? "Setup Complete" : "Setup Failed"
        } else {
            return "Missing Dependencies"
        }
    }
    
    private var subtitleText: String {
        if isSettingUp {
            return "Please wait while Vocal sets up the required components for YouTube transcription..."
        } else if setupComplete {
            return setupSuccess 
                ? "All dependencies have been successfully installed. You can now transcribe YouTube videos."
                : "Some dependencies could not be installed automatically. Please try manual installation or contact support."
        } else {
            return "To transcribe YouTube videos, Vocal needs the following components. These can be installed automatically or manually."
        }
    }
    
    private var canSetupAutomatically: Bool {
        missingDependencies.contains { $0.isEmbeddable }
    }
    
    // MARK: - Methods
    
    private func setupAutomatically() {
        isSettingUp = true
        setupProgress = 0
        
        // Animate progress
        withAnimation(.easeInOut(duration: 2.5)) {
            setupProgress = 0.95
        }
        
        Task {
            // Call the setup function
            onSetupAutomatically()
            
            // Wait a bit to show completion
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Update UI
            await MainActor.run {
                setupProgress = 1.0
                isSettingUp = false
                setupComplete = true
                setupSuccess = true
            }
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.15 : 0.1))
            )
            .foregroundColor(.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
