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
    @FocusState private var isTextFieldFocused: Bool
    
    private let minWindowWidth: CGFloat = 600
    private let minWindowHeight: CGFloat = 700
    
    var body: some View {
        ZStack {
            // Background blur effect
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
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
        VStack(spacing: 24) {
            DropZoneView(
                isDragging: $isDragging,
                onTap: handleFileSelection
            )
            
            if showYouTubeRepairOption {
                VStack(spacing: 12) {
                    Text("Having issues with YouTube transcription?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Repair YouTube Setup") {
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
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 8)
                .transition(.opacity)
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
        Button(action: { isSearching.toggle() }) {
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
                Button(action: { searchText = "" }) {
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
                if detail.isEmpty {
                    EmptyView()
                } else {
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
            }
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.03))
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
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.red)
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
                    .buttonStyle(PrimaryButtonStyle())
                    
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
                    .buttonStyle(PrimaryButtonStyle())
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
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.red.opacity(0.1), lineWidth: 1)
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
            do {
                let dependencies = await SystemDependencyChecker.checkDependencies()
                let hasYouTubeDependencyIssues = dependencies.contains(where: { dependency in
                    dependency.dependency.rawValue.contains("yt-dlp") || 
                    dependency.dependency.rawValue.contains("ffmpeg")
                })
                
                await MainActor.run {
                    showYouTubeRepairOption = hasYouTubeDependencyIssues
                }
            } catch {
                print("Failed to check YouTube setup: \(error)")
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
            manager.clearContent()
        }
    }
}

