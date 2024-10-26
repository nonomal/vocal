import SwiftUI
import AVFoundation
import Speech
import AVKit
import UniformTypeIdentifiers

class TranscriptionManager: ObservableObject {
    @Published var isLoading = false
    @Published var videoURL: URL?
    @Published var transcription: String = ""
    @Published var uploadState: UploadState = .idle
    @Published var progress: Double = 0
    @Published var downloadProgress: String = ""
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    enum UploadState {
        case idle
        case uploading
        case processing
        case completed
        case error(String)
    }
    
    enum TranscriptionError: Error {
        case noAudioTracks
        case authorizationDenied
        case invalidFile
        case processingError(String)
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
                self.uploadState = .uploading
                self.videoURL = url
                
                guard await requestSpeechAuthorization() else {
                    throw TranscriptionError.authorizationDenied
                }
                
                try await transcribeVideo(url)
            } catch {
                handleError(error)
            }
        }
    }
    
    func handleYouTubeURL(_ urlString: String) {
        Task { @MainActor in
            do {
                guard YouTubeManager.isValidYouTubeURL(urlString) else {
                    throw YouTubeManager.YouTubeError.invalidURL
                }
                
                self.uploadState = .uploading
                self.isLoading = true
                
                // Download video
                let videoURL = try await YouTubeManager.downloadVideo(from: urlString) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                
                // Process the downloaded video
                try await transcribeVideo(videoURL)
                
                // Cleanup downloaded video
                try? FileManager.default.removeItem(at: videoURL)
                
            } catch YouTubeManager.YouTubeError.ytDlpNotFound {
                self.uploadState = .error("Internal yt-dlp not found. Please contact support.")
            } catch YouTubeManager.YouTubeError.setupFailed {
                self.uploadState = .error("Failed to initialize yt-dlp. Please contact support.")
            } catch YouTubeManager.YouTubeError.invalidURL {
                self.uploadState = .error("Invalid YouTube URL")
            } catch YouTubeManager.YouTubeError.permissionDenied {
                self.uploadState = .error("Permission denied when trying to download video.")
            } catch YouTubeManager.YouTubeError.downloadFailed(let message) {
                self.uploadState = .error("Download failed: \(message)")
            } catch {
                self.uploadState = .error(error.localizedDescription)
            }
            
            self.downloadProgress = ""
        }
    }
    
    private func handleError(_ error: Error) {
        let errorMessage: String
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .noAudioTracks:
                errorMessage = "No audio tracks found in the video file"
            case .authorizationDenied:
                errorMessage = "Speech recognition authorization denied"
            case .invalidFile:
                errorMessage = "Invalid video file"
            case .processingError(let message):
                errorMessage = message
            }
        } else {
            errorMessage = error.localizedDescription
        }
        
        Task { @MainActor in
            self.uploadState = .error(errorMessage)
            self.isLoading = false
        }
    }
    
    func clearContent() {
        videoURL = nil
        transcription = ""
        uploadState = .idle
        isLoading = false
        progress = 0
        stopRecognition()
    }
    
    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    private func transcribeVideo(_ url: URL) async throws {
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              speechRecognizer.isAvailable else {
            throw TranscriptionError.processingError("Speech recognition is not available")
        }
        
        await MainActor.run {
            self.isLoading = true
            self.uploadState = .processing
        }
        
        // Create asset and verify audio tracks
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard !audioTracks.isEmpty else {
            throw TranscriptionError.noAudioTracks
        }
        
        let duration = try await asset.load(.duration).seconds
        
        // Create audio file from video
        let audioURL = try await extractAudio(from: url)
        
        try await transcribeAudioFile(audioURL, speechRecognizer: speechRecognizer, duration: duration)
        
        // Cleanup temporary file
        try? FileManager.default.removeItem(at: audioURL)
        
        await MainActor.run {
            self.isLoading = false
            self.uploadState = .completed
        }
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
            throw TranscriptionError.processingError("Could not create export session")
        }
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a
        exportSession.audioTimePitchAlgorithm = .spectral
        
        await exportSession.export()
        
        if let error = exportSession.error {
            throw TranscriptionError.processingError("Failed to extract audio: \(error.localizedDescription)")
        }
        
        guard exportSession.status == .completed else {
            throw TranscriptionError.processingError("Export failed with status: \(exportSession.status.rawValue)")
        }
        
        return tempURL
    }
    
    private func transcribeAudioFile(_ audioURL: URL, speechRecognizer: SFSpeechRecognizer, duration: Double) async throws {
        print("Starting transcription of audio file: \(audioURL.path)")
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    print("Recognition error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else { return }
                
                Task { @MainActor in
                    self?.transcription = result.bestTranscription.formattedString
                    if let currentTime = result.bestTranscription.segments.last?.timestamp {
                        self?.progress = min(currentTime / duration, 1.0)
                    }
                    
                    if result.isFinal {
                        print("Transcription completed")
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
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if manager.isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        if !manager.downloadProgress.isEmpty {
                            Text("Downloading YouTube video...")
                                .font(.headline)
                                .padding(.bottom, 4)
                            Text(manager.downloadProgress)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Transcribing... \(Int(manager.progress * 100))%")
                                .foregroundColor(.secondary)
                        }
                    }
                } else if !manager.transcription.isEmpty {
                    ScrollView {
                        Text(manager.transcription)
                            .padding()
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.8))
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
                } else {
                    DropZoneView(
                                            isDragging: $isDragging,
                                            onTap: handleFileSelection,
                                            onPaste: { urlString in
                                                if YouTubeManager.isValidYouTubeURL(urlString) {
                                                    manager.handleYouTubeURL(urlString)
                                                }
                                            }
                                        )
                                    }
                                    
                                    if case .error(let message) = manager.uploadState {
                                        Text(message)
                                            .foregroundColor(.red)
                                            .padding()
                                            .background(Color.primary.opacity(0.05))
                                            .cornerRadius(8)
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
    
    private func loadFirstProvider(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error = error {
                    print("Error loading URL: \(error)")
                    Task { @MainActor in
                        self.manager.uploadState = .error("Failed to load dropped file")
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
                manager.uploadState = .error("Failed to save transcription: \(error.localizedDescription)")
            }
        }
    }
}
