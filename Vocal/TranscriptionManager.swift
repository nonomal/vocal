import Foundation
import Speech

enum TranscriptionState {
    case idle
    case downloading(progress: String)
    case preparingAudio
    case transcribing(progress: Double)
    case completed
    case error(String)
}

@MainActor
class TranscriptionManager: ObservableObject {
    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var downloadState: DownloadState = .idle
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var transcription: String = ""
    @Published var videoURL: URL?
    @Published private(set) var segments: [TranscriptionSegment] = []
    @Published var progress: Double = 0
    @Published var wordCount: Int = 0
    @Published var estimatedReadingTime: TimeInterval = 0
    
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tempFiles: [URL] = []
    private var currentBuffer: String = ""
    private let paragraphBreakThreshold: TimeInterval = 2.0
    
    public struct TranscriptionSegment: Equatable, Sendable {
        public let text: String
        public let timestamp: TimeInterval
        public let isFinal: Bool
        
        var isPunctuation: Bool {
            guard let lastChar = text.last else { return false }
            return [".","!","?"].contains(lastChar)
        }
        
        var isNaturalBreak: Bool {
            isPunctuation || text.count >= 150
        }
    }
    
    private let minSegmentLength = 100
    private let maxSegmentLength = 250
    private let wordsPerMinute: Double = 200
    
    deinit {
        Task { @MainActor in
            await cleanupTempFiles()
        }
    }
    
    @MainActor
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
        Task {
            do {
                guard YouTubeManager.isValidYouTubeURL(urlString) else {
                    await MainActor.run {
                        self.state = .error("Invalid YouTube URL")
                    }
                    return
                }
                
                await MainActor.run {
                    self.downloadState = .downloading(progress: 0, speed: nil, eta: nil)
                    self.resetTranscription()
                }
                
                let videoURL = try await downloadYouTubeVideo(urlString)
                
                await MainActor.run {
                    self.tempFiles.append(videoURL)
                    self.state = .preparingAudio
                }
                
                try await transcribeVideo(videoURL)
                
                await MainActor.run {
                    self.finalizeTranscription()
                    self.state = .completed
                    self.downloadState = .idle
                }
                
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                    self.downloadState = .idle
                }
                print("YouTube download/transcription error: \(error)")
            }
        }
    }
    
    private func resetTranscription() {
        transcription = ""
        currentBuffer = ""
        segments.removeAll()
        progress = 0
        downloadProgress = 0
        wordCount = 0
        estimatedReadingTime = 0
    }
    
    private func addSegment(_ segment: TranscriptionSegment) {
        if segments.last?.text != segment.text {
            if segment.isFinal {
                segments.append(segment)
            }
            formatAndPublishTranscription()
        }
    }
    
    @MainActor
    private func formatAndPublishTranscription() {
        var formattedText = ""
        var currentParagraph = ""
        
        for (index, segment) in segments.enumerated() {
            currentParagraph += segment.text.trimmingCharacters(in: .whitespacesAndNewlines) + " "
            
            let shouldBreak = segment.isNaturalBreak || 
                            (index < segments.count - 1 && 
                             segments[index + 1].timestamp - segment.timestamp > paragraphBreakThreshold)
            
            if shouldBreak {
                formattedText += currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                currentParagraph = ""
            }
        }
        
        if !currentParagraph.isEmpty {
            formattedText += currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        self.transcription = formattedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func finalizeTranscription() {
        formatAndPublishTranscription()
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
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
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
                    
                    await exportSession.export()
                    
                    if let error = exportSession.error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard exportSession.status == .completed else {
                        continuation.resume(throwing: NSError(domain: "", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Export failed with status: \(exportSession.status.rawValue)"]))
                        return
                    }
                    
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func transcribeAudioFile(_ audioURL: URL, speechRecognizer: SFSpeechRecognizer, duration: Double) async throws {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation // Optimize for continuous speech
        
        // Use a debouncer for progress updates
        let progressDebouncer = Debouncer(delay: 0.1)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else { return }
                
                Task { @MainActor in
                    if let lastSegment = result.bestTranscription.segments.last {
                        let segment = TranscriptionSegment(
                            text: result.bestTranscription.formattedString,
                            timestamp: lastSegment.timestamp,
                            isFinal: result.isFinal
                        )
                        
                        self.addSegment(segment)
                        
                        // Update progress with debouncing
                        progressDebouncer.debounce {
                            self.progress = min(lastSegment.timestamp / duration, 1.0)
                            self.state = .transcribing(progress: self.progress)
                        }
                    }
                    
                    if result.isFinal {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func clearContent() {
        videoURL = nil
        transcription = ""
        currentBuffer = ""
        segments.removeAll()
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
    
    private func downloadYouTubeVideo(_ url: String) async throws -> URL {
        return try await YouTubeManager.downloadVideo(from: url) { [weak self] progressLine in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.updateDownloadProgress(progressLine)
            }
        }
    }
    
    @MainActor
    private func updateDownloadProgress(_ progressLine: String) {
        // Parse the progress line
        if let percentStr = progressLine.split(separator: " ").first,
           let percent = Double(percentStr.replacingOccurrences(of: "%", with: "")) {
            let progress = percent / 100.0
            self.downloadProgress = progress
            
            // Extract speed and ETA if available
            let components = progressLine.split(separator: " ")
            var speed: String?
            var eta: String?
            
            for component in components {
                if component.hasSuffix("/s") {
                    speed = String(component)
                } else if component.contains("ETA") {
                    eta = String(component.replacingOccurrences(of: "ETA", with: "").trimmingCharacters(in: .whitespaces))
                }
            }
            
            self.downloadState = .downloading(progress: progress, speed: speed, eta: eta)
        }
    }
    
    @MainActor
    func handleError(_ message: String) {
        state = .error(message)
    }
}

enum DownloadState {
    case idle
    case downloading(progress: Double, speed: String?, eta: String?)
    case processing
    
    var progressText: String {
        switch self {
        case .idle:
            return "Ready"
        case .downloading(let progress, let speed, let eta):
            var text = "\(Int(progress * 100))%"
            if let speed = speed {
                text += " • \(speed)"
            }
            if let eta = eta {
                text += " • \(eta)"
            }
            return text
        case .processing:
            return "Processing..."
        }
    }
}

// Debouncer utility class
private class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    
    init(delay: TimeInterval) {
        self.delay = delay
    }
    
    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }
}
