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
    
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tempFiles: [URL] = []
    private var transcriptionBuffer: String = ""
    private var finalTranscriptionSegments: [String] = []
    private var currentSegment: String = ""
    
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
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition authorization denied"])
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
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid YouTube URL"])
                }
                
                state = .downloading(progress: "Initializing...")
                resetTranscription()
                
                let videoURL = try await YouTubeManager.downloadVideo(from: urlString) { progress in
                    Task { @MainActor in
                        self.state = .downloading(progress: progress)
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
        currentSegment = ""
        progress = 0
    }
    
    private func finalizeTranscription() {
        if !currentSegment.isEmpty {
            finalTranscriptionSegments.append(currentSegment)
        }
        transcription = finalTranscriptionSegments.joined(separator: " ")
        print("Final transcription length: \(transcription.count) characters")
    }
    
    func clearContent() {
        videoURL = nil
        transcription = ""
        transcriptionBuffer = ""
        finalTranscriptionSegments.removeAll()
        currentSegment = ""
        state = .idle
        progress = 0
        stopRecognition()
        cleanupTempFiles()
    }
    
    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    private func transcribeVideo(_ url: URL) async throws {
        print("Starting transcription for video at: \(url.path)")
        
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              speechRecognizer.isAvailable else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available"])
        }
        
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard !audioTracks.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio tracks found in the video"])
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
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
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
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed with status: \(exportSession.status.rawValue)"])
        }
        
        return tempURL
    }
    
    private func transcribeAudioFile(_ audioURL: URL, speechRecognizer: SFSpeechRecognizer, duration: Double) async throws {
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
                    
                    // Only update if we have new content
                    if newText != self.currentSegment {
                        // If we have a substantial difference, commit the current segment
                        if self.currentSegment.count > 0 &&
                           abs(self.currentSegment.count - newText.count) > 10 {
                            self.finalTranscriptionSegments.append(self.currentSegment)
                            self.currentSegment = newText
                        } else {
                            self.currentSegment = newText
                        }
                        
                        // Update the displayed transcription
                        self.transcription = (self.finalTranscriptionSegments + [self.currentSegment])
                            .joined(separator: " ")
                    }
                    
                    // Update progress
                    if let currentTime = result.bestTranscription.segments.last?.timestamp {
                        self.progress = min(currentTime / duration, 1.0)
                        self.state = .transcribing(progress: self.progress)
                    }
                    
                    if result.isFinal {
                        print("Transcription completed")
                        // Commit the final segment if we have one
                        if !self.currentSegment.isEmpty {
                            self.finalTranscriptionSegments.append(self.currentSegment)
                            self.currentSegment = ""
                            self.transcription = self.finalTranscriptionSegments.joined(separator: " ")
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var manager = TranscriptionManager()
    @State private var isDragging = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if case .transcribing = manager.state,
                   !manager.transcription.isEmpty {
                    transcriptionView
                } else if case .completed = manager.state {
                    transcriptionView
                } else if case .downloading(let progress) = manager.state {
                    loadingView(message: "Downloading video...", detail: progress)
                } else if case .preparingAudio = manager.state {
                    loadingView(message: "Preparing audio...", detail: "")
                } else if case .transcribing(let progress) = manager.state {
                    loadingView(message: "Transcribing...", detail: "\(Int(progress * 100))%")
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
        .frame(minWidth: 600, minHeight: 700)
        .onAppear {
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
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            loadFirstProvider(from: providers)
            return true
        }
    }
    
    private var transcriptionView: some View {
        VStack {
            ScrollView {
                Text(manager.transcription)
                    .padding()
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
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
    
    private func loadingView(message: String, detail: String) -> some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
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
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
                .padding()
            
            Text(message)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                manager.clearContent()
            }
            .padding(.top)
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
