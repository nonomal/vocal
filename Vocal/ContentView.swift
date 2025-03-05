import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers


struct ContentView: View {
    @StateObject private var manager = TranscriptionManager()
    @State private var isDragging = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showYouTubeRepairOption = false
    @State private var isRepairHovered = false
    @FocusState private var isTextFieldFocused: Bool
    
    private let minWindowWidth: CGFloat = 600
    private let minWindowHeight: CGFloat = 700
    
    var body: some View {
        ZStack {
            // Background blur effect with subtle gradient overlay
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.02),
                            Color.purple.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Main content area
                if case .checkingDependencies = manager.state {
                    loadingView(
                        message: "Checking system requirements...",
                        progress: nil,
                        detail: "This may take a moment"
                    )
                } else if case .transcribing = manager.state,
                          !manager.transcription.isEmpty {
                    transcriptionView
                } else if case .completed = manager.state {
                    transcriptionView
                } else if case .downloading(let progress, let speed, let eta, _) = manager.downloadState {
                    loadingView(
                        message: "Downloading YouTube video...",
                        progress: progress,
                        detail: "\(speed ?? "") \(eta ?? "")"
                    )
                } else if case .preparingAudio = manager.state {
                    loadingView(
                        message: "Preparing audio...",
                        progress: nil,
                        detail: "Extracting audio from video"
                    )
                } else if case .transcribing(let progress, _) = manager.state {
                    loadingView(
                        message: "Transcribing...",
                        progress: progress,
                        detail: "\(Int(progress * 100))% complete"
                    )
                } else if case .error(let message) = manager.state {
                    errorView(message: message)
                } else {
                    mainDropZoneView
                }
            }
            .padding(30)
        }
        .frame(minWidth: minWindowWidth, minHeight: minWindowHeight)
        .onAppear {
            setupPasteboardMonitoring()
            checkYouTubeSetup()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            loadFirstProvider(from: providers)
            return true
        }
        .sheet(isPresented: $manager.showDependencyAlert) {
            DependencyAlertView(
                missingDependencies: manager.missingDependencies,
                onDismiss: { manager.showDependencyAlert = false },
                onSetupAutomatically: {
                    Task {
                        _ = await SystemDependencyChecker.setupMissingDependencies()
                    }
                }
            )
        }
    }
    
    // MARK: - Subviews
    
    private var mainDropZoneView: some View {
        ZStack(alignment: .bottom) {
            // Main drop zone
            DropZoneView(
                isDragging: $isDragging,
                onTap: handleFileSelection
            )
            
            // YouTube repair button shown as a subtle pill at the bottom
            if showYouTubeRepairOption {
                repairButton
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private var repairButton: some View {
        Button(action: {
            Task {
                do {
                    try await YouTubeManager.repairSetup()
                    await MainActor.run {
                        showYouTubeRepairOption = false
                    }
                } catch {
                    print("Failed to repair YouTube setup: \(error)")
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 10))
                Text("Repair YouTube Setup")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Color.primary.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isRepairHovered ? 1.02 : 1.0)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isRepairHovered = hovering
            }
        }
    }
    
    private var transcriptionView: some View {
        VStack(spacing: 16) {
            // Transcription statistics
            HStack {
                statsView
                Spacer()
                if !manager.transcription.isEmpty {
                    searchToggle
                }
            }
            
            // Search bar when searching is active
            if isSearching {
                searchBar
            }
            
            // Main transcription area with adaptive text
            AdaptiveTextView(text: manager.transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Action buttons
            ButtonGroup(buttons: [
                (
                    title: "Copy",
                    icon: "doc.on.doc",
                    action: { copyTranscriptionToPasteboard() }
                ),
                (
                    title: "Save",
                    icon: "arrow.down.circle",
                    action: { saveTranscription() }
                ),
                (
                    title: "Clear",
                    icon: "trash",
                    action: { manager.clearContent() }
                )
            ])
        }
    }
    
    private var statsView: some View {
        HStack(spacing: 16) {
            StatisticView(
                icon: "textformat",
                value: "\(wordCount)",
                label: "words"
            )
            StatisticView(
                icon: "clock",
                value: readingTime,
                label: "read time"
            )
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    private var searchToggle: some View {
        Button(action: { 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isSearching.toggle() 
            }
        }) {
            Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                .foregroundColor(.secondary)
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search in transcription", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .focused($isTextFieldFocused)
            
            if !searchText.isEmpty {
                Button(action: { 
                    withAnimation(.spring()) {
                        searchText = "" 
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
        .cornerRadius(8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func loadingView(message: String, progress: Double?, detail: String) -> some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Loading icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                if let progress = progress {
                    // Circular progress indicator
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 80, height: 80)
                        .animation(.easeInOut, value: progress)
                    
                    // Percentage in center
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                } else {
                    // Indeterminate spinner
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            
            VStack(spacing: 16) {
                // Main message
                Text(message)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                // Detail text with dynamic resizing
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300)
                        .animation(.easeInOut, value: detail)
                }
                
                // Only show progress bar for certain states
                if let progress = progress, message.contains("Downloading") || message.contains("Transcribing") {
                    VStack(spacing: 4) {
                        // Progress bar
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: 300)
                            .animation(.easeInOut, value: progress)
                    }
                    .padding(.top, 8)
                }
            }
            
            // Add a cancel button for long-running operations
            if message.contains("Downloading") || message.contains("Transcribing") {
                Button("Cancel") {
                    cancelOperation()
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 16)
                .transition(.opacity)
            }
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Error icon with animation
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.red.opacity(0.8))
            }
            
            VStack(spacing: 16) {
                Text("Error")
                    .font(.title2.bold())
                
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }
            
            VStack(spacing: 12) {
                // Show appropriate action buttons based on error type
                if message.contains("YouTube") || message.contains("yt-dlp") || message.contains("download") {
                    Button("Repair YouTube Setup") {
                        Task {
                            do {
                                try await YouTubeManager.repairSetup()
                                await MainActor.run {
                                    manager.clearContent()
                                }
                            } catch {
                                print("Failed to repair YouTube setup: \(error)")
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    // Add a help text for context
                    Text("This will reinstall the necessary components for YouTube transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // If authorization related, show open settings button
                if message.contains("authorization") || message.contains("denied") || message.contains("Privacy") {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                
                // Always provide a dismiss button
                Button("Dismiss") {
                    manager.clearContent()
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 8)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.red.opacity(0.08), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    // MARK: - Helper Views
    
    private struct StatisticView: View {
        let icon: String
        let value: String
        let label: String
        
        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(value)
                    .fontWeight(.medium)
                Text(label)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var wordCount: Int {
        manager.transcription.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    private var readingTime: String {
        let minutes = Double(wordCount) / 200.0 // Average reading speed
        if minutes < 1 {
            return "< 1 min"
        }
        return "\(Int(ceil(minutes))) min"
    }
    
    // MARK: - Functions
    
    private func checkYouTubeSetup() {
        Task {
            let dependencies = await SystemDependencyChecker.checkDependencies()
            let hasYouTubeDependencyIssues = dependencies.contains(where: { dependency in
                dependency.dependency.rawValue.contains("yt-dlp") || 
                dependency.dependency.rawValue.contains("ffmpeg")
            })
            
            await MainActor.run {
                withAnimation(.spring()) {
                    showYouTubeRepairOption = hasYouTubeDependencyIssues
                }
            }
        }
    }
    
    private func setupPasteboardMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.characters?.lowercased() == "v" {
                if let urlString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    print("Attempting to handle URL: \(urlString)") // Debug log
                    if YouTubeManager.isValidYouTubeURL(urlString) {
                        Task { @MainActor in
                            manager.handleYouTubeURL(urlString)
                        }
                        return nil // Consume the event when we handle it
                    }
                }
            }
            return event
        }
    }
    
    private func loadFirstProvider(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error = error {
                    print("Error loading URL: \(error)")
                    Task { @MainActor in
                        manager.handleError("Failed to load dropped file")
                    }
                    return
                }
                
                if let url = url {
                    handleVideoURL(url)
                }
            }
        }
    }
    
    private func handleVideoURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        Task { @MainActor in
            manager.handleVideoSelection(url)
        }
    }
    
    private func handleFileSelection() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.movie,
            UTType.video,
            UTType.mpeg2Video
        ]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                handleVideoURL(url)
            }
        }
    }
    
    private func copyTranscriptionToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(manager.transcription, forType: .string)
        
        // Add a subtle feedback animation here
        let generator = NSHapticFeedbackManager.defaultPerformer
        generator.perform(.generic, performanceTime: .default)
    }
    
    private func saveTranscription() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Transcription"
        savePanel.message = "Choose a location to save the transcription"
        savePanel.nameFieldStringValue = "transcription.txt"
        
        let response = savePanel.runModal()
        
        if response == .OK,
           let url = savePanel.url {
            do {
                try manager.transcription.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Task { @MainActor in
                    manager.handleError("Failed to save transcription: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func cancelOperation() {
        Task { @MainActor in
            withAnimation(.spring()) {
                manager.clearContent()
            }
        }
    }
}

