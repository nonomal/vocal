import SwiftUI
import AVFoundation
import Speech
import AVKit
import UniformTypeIdentifiers

enum TranscriptionState {
    case idle
    case downloading(progress: String)
    case preparingAudio
    case transcribing(progress: Double)
    case completed
    case error(String)
}

class TranscriptionManager: ObservableObject {
    @Published var state: TranscriptionState = .idle
    @Published var videoURL: URL?
    @Published var transcription: String = ""
    @Published var progress: Double = 0
    @Published var downloadProgress: Double = 0
    @Published var wordCount: Int = 0
    @Published var estimatedReadingTime: TimeInterval = 0
    
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tempFiles: [URL] = []
    private var transcriptionBuffer: String = ""
    private var finalTranscriptionSegments: [TranscriptionSegment] = []
    private var currentSegment: TranscriptionSegment?
    
    private struct TranscriptionSegment {
        let text: String
        let timestamp: TimeInterval
        var isPunctuation: Bool {
            text.last?.isPunctuation ?? false
        }
    }
    
    private let minSegmentLength = 100
    private let maxSegmentLength = 250
    private let wordsPerMinute: Double = 200
    
    deinit {
        cleanupTempFiles()
    }
    
    private func cleanupTempFiles() {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
    }
    
    func requestSpeechAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }
    
    func handleVideoSelection(_ url: URL) {
        Task { @MainActor in
            do {
                state = .preparingAudio
                videoURL = url
                
                guard await requestSpeechAuthorization() else {
                    throw NSError(domain: "", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Speech recognition authorization denied"])
                }
                
                resetTranscription()
                try await transcribeVideo(url)
                finalizeTranscription()
                state = .completed
            } catch {
                state = .error(error.localizedDescription)
                print("Transcription error: \(error)")
            }
        }
    }
    
    func handleYouTubeURL(_ urlString: String) {
        Task { @MainActor in
            do {
                guard YouTubeManager.isValidYouTubeURL(urlString) else {
                    throw NSError(domain: "", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid YouTube URL"])
                }
                
                state = .downloading(progress: "Starting download...")
                resetTranscription()
                
                let videoURL = try await YouTubeManager.downloadVideo(from: urlString) { progress in
                    Task { @MainActor in
                        if let percentStr = progress.split(separator: " ").first,
                           let percent = Double(percentStr.replacingOccurrences(of: "%", with: "")) {
                            self.downloadProgress = percent / 100.0
                            self.state = .downloading(progress: "\(Int(percent))%")
                        } else {
                            self.state = .downloading(progress: progress)
                        }
                    }
                }
                
                tempFiles.append(videoURL)
                state = .preparingAudio
                try await transcribeVideo(videoURL)
                finalizeTranscription()
                state = .completed
                
            } catch {
                state = .error(error.localizedDescription)
                print("YouTube download/transcription error: \(error)")
            }
        }
    }
    
    private func resetTranscription() {
        transcription = ""
        transcriptionBuffer = ""
        finalTranscriptionSegments.removeAll()
        currentSegment = nil
        progress = 0
        downloadProgress = 0
        wordCount = 0
        estimatedReadingTime = 0
    }
    
    private func formatTranscription() -> String {
        var formattedText = ""
        var currentParagraph = ""
        
        for segment in finalTranscriptionSegments {
            currentParagraph += segment.text + " "
            
            if segment.isPunctuation && currentParagraph.count >= minSegmentLength {
                formattedText += currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                currentParagraph = ""
            }
            
            if currentParagraph.count >= maxSegmentLength {
                formattedText += currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                currentParagraph = ""
            }
        }
        
        if !currentParagraph.isEmpty {
            formattedText += currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Calculate word count and reading time
        let words = formattedText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        wordCount = words.count
        estimatedReadingTime = Double(wordCount) / wordsPerMinute
        
        return formattedText
    }
    
    private func finalizeTranscription() {
        if let currentSegment = currentSegment {
            finalTranscriptionSegments.append(currentSegment)
        }
        transcription = formatTranscription()
        print("Final transcription length: \(transcription.count) characters")
    }
    
    private func transcribeVideo(_ url: URL) async throws {
        print("Starting transcription for video at: \(url.path)")
        
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              speechRecognizer.isAvailable else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available"])
        }
        
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard !audioTracks.isEmpty else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No audio tracks found in the video"])
        }
        
        let duration = try await asset.load(.duration).seconds
        print("Video duration: \(duration) seconds")
        
        let audioURL = try await extractAudio(from: url)
        tempFiles.append(audioURL)
        print("Audio extracted to: \(audioURL.path)")
        
        try await transcribeAudioFile(audioURL, speechRecognizer: speechRecognizer, duration: duration)
    }
    
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        let asset = AVURLAsset(url: videoURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
        }
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a
        exportSession.audioTimePitchAlgorithm = .spectral
        
        print("Starting audio extraction...")
        await exportSession.export()
        
        if let error = exportSession.error {
            print("Audio extraction failed: \(error)")
            throw error
        }
        
        guard exportSession.status == .completed else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Export failed with status: \(exportSession.status.rawValue)"])
        }
        
        return tempURL
    }
    
    private func transcribeAudioFile(_ audioURL: URL,
                                   speechRecognizer: SFSpeechRecognizer,
                                   duration: Double) async throws {
        print("Starting transcription of audio file: \(audioURL.path)")
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Recognition error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else { return }
                
                Task { @MainActor in
                    let newText = result.bestTranscription.formattedString
                    
                    if let timestamp = result.bestTranscription.segments.last?.timestamp {
                        let newSegment = TranscriptionSegment(text: newText, timestamp: timestamp)
                        
                        if newText != self.currentSegment?.text {
                            if let current = self.currentSegment,
                               abs(current.text.count - newText.count) > 10 {
                                self.finalTranscriptionSegments.append(current)
                            }
                            self.currentSegment = newSegment
                            
                            self.transcription = self.formatTranscription()
                        }
                        
                        self.progress = min(timestamp / duration, 1.0)
                        self.state = .transcribing(progress: self.progress)
                    }
                    
                    if result.isFinal {
                        print("Transcription completed")
                        if let current = self.currentSegment {
                            self.finalTranscriptionSegments.append(current)
                            self.currentSegment = nil
                            self.transcription = self.formatTranscription()
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func clearContent() {
        videoURL = nil
        transcription = ""
        transcriptionBuffer = ""
        finalTranscriptionSegments.removeAll()
        currentSegment = nil
        state = .idle
        progress = 0
        downloadProgress = 0
        wordCount = 0
        estimatedReadingTime = 0
        stopRecognition()
        cleanupTempFiles()
    }
    
    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}


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
                } else if case .downloading(let progress) = manager.state {
                    loadingView(
                        message: "Downloading video...",
                        progress: manager.downloadProgress,
                        detail: progress
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
                if let urlString = NSPasteboard.general.string(forType: .string) {
                    if YouTubeManager.isValidYouTubeURL(urlString) {
                        manager.handleYouTubeURL(urlString)
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
                        manager.state = .error("Failed to load dropped file")
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
                manager.state = .error("Failed to save transcription: \(error.localizedDescription)")
            }
        }
    }
}
