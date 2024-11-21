import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers


struct ContentView: View {
    @StateObject private var manager = TranscriptionManager()
    @State private var isDragging = false
    @State private var isSearching = false
    @State private var searchText = ""
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
                } else if case .downloading = manager.downloadState {
                    loadingView(
                        message: "Downloading video...",
                        progress: manager.downloadProgress,
                        detail: manager.downloadState.progressText
                    )
                } else if case .preparingAudio = manager.state {
                    loadingView(
                        message: "Preparing audio...",
                        progress: nil,
                        detail: "Extracting audio from video"
                    )
                } else if case .transcribing(let progress, let currentText) = manager.state {
                    loadingView(
                        message: "Transcribing...",
                        progress: progress,
                        detail: "\(Int(progress * 100))% - Currently processing: \(currentText.suffix(50))..."
                    )
                } else if case .error(let message) = manager.state {
                    errorView(message: message)
                } else {
                    DropZoneView(
                        isDragging: $isDragging,
                        onTap: handleFileSelection
                    )
                }
            }
            .padding(30)
        }
        .frame(minWidth: minWindowWidth, minHeight: minWindowHeight)
        .onAppear {
            setupPasteboardMonitoring()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            loadFirstProvider(from: providers)
            return true
        }
        .sheet(isPresented: $manager.showDependencyAlert) {
            DependencyAlertView(
                missingDependencies: manager.missingDependencies,
                onDismiss: { manager.showDependencyAlert = false }
            )
        }
    }
    
    // MARK: - Subviews
    
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
            ScrollView {
                if manager.transcription.count < 500 {
                    AdaptiveTextView(text: manager.transcription)
                        .padding()
                        .textSelection(.enabled)
                } else {
                    Text(manager.transcription)
                        .padding()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(4)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
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
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func loadingView(message: String, progress: Double?, detail: String) -> some View {
        VStack(spacing: 24) {
            // Main progress container
            VStack(spacing: 16) {
                // Title and progress percentage
                HStack {
                    Text(message)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let progress = progress {
                        Text("\(Int(progress * 100))%")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let progress = progress {
                    // Modern progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 4)
                            
                            // Progress fill with gradient
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.accentColor,
                                            Color.accentColor.opacity(0.8)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 4)
                                .animation(.linear(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 4)
                    
                    // Download stats container
                    if case .downloading(_, let speed, let eta, let size) = manager.downloadState {
                        HStack(spacing: 16) {
                            // Speed indicator
                            if let speed = speed {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text(speed)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Divider
                            if speed != nil && (eta != nil || size != nil) {
                                Text("·")
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            
                            // ETA
                            if let eta = eta {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(.accentColor.opacity(0.8))
                                    Text(eta.replacingOccurrences(of: "ETA: ", with: ""))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Divider
                            if eta != nil && size != nil {
                                Text("·")
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            
                            // File size
                            if let size = size {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.accentColor.opacity(0.6))
                                    Text(size)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .font(.system(.caption, design: .rounded))
                        .padding(.top, 8)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            .frame(maxWidth: 400)
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text(message)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                manager.clearContent()
            }
        }
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
}

