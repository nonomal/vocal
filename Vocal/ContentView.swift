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
                if case .transcribing = manager.state,
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
                        detail: ""
                    )
                } else if case .transcribing(let progress) = manager.state {
                    loadingView(
                        message: "Transcribing...",
                        progress: progress,
                        detail: "\(Int(progress * 100))%"
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
            
            // Main transcription text area
            ScrollView {
                Text(manager.transcription)
                    .padding()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
                    .font(.body)
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
                icon: "text.word.count",
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
        VStack(spacing: 12) {
            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
            
            Text(message)
                .font(.headline)
            
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
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
