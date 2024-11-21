import Foundation
import Speech
import SwiftUI

enum TranscriptionState {
    case idle
    case checkingDependencies
    case downloading(progress: Double, speed: String?, eta: String?)
    case preparingAudio(progress: Double)
    case transcribing(progress: Double, currentText: String)
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
    @Published private(set) var missingDependencies: [DependencyStatus] = []
    @Published var showDependencyAlert = false
    @Published private(set) var processingProgress: Double = 0
    @Published private(set) var currentSegmentText: String = ""
    
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
        print("Requesting speech recognition authorization")
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                print("Speech recognition authorization status: \(status.rawValue)")
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied:
                    print("Speech recognition denied")
                case .restricted:
                    print("Speech recognition restricted")
                case .notDetermined:
                    print("Speech recognition not determined")
                @unknown default:
                    print("Speech recognition unknown status")
                }
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }
    
    func handleVideoSelection(_ url: URL) {
        Task { @MainActor in
            do {
                state = .checkingDependencies
                
                // Quick dependency check with timeout
                let dependencyTask = Task {
                    return await checkDependencies()
                }
                
                let hasRequirements = try await withTimeout(of: 5) {
                    try await dependencyTask.value
                }
                
                guard hasRequirements else { return }
                
                state = .preparingAudio(progress: 0)
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
                await MainActor.run { self.state = .checkingDependencies }
                
                // Quick dependency check with timeout
                let dependencyTask = Task {
                    return await checkDependencies()
                }
                
                let hasRequirements = try await withTimeout(of: 5) {
                    try await dependencyTask.value
                }
                
                guard hasRequirements else { return }
                
                guard YouTubeManager.isValidYouTubeURL(urlString) else {
                    await MainActor.run { self.state = .error("Invalid YouTube URL") }
                    return
                }
                
                await MainActor.run {
                    self.resetTranscription()
                }
                
                let videoURL = try await downloadYouTubeVideo(urlString)
                
                await MainActor.run {
                    self.tempFiles.append(videoURL)
                    self.state = .preparingAudio(progress: 0)
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
        print("Adding segment: \(segment.text)")  // Debug logging
        
        if segments.last?.text != segment.text {
            if segment.isFinal {
                segments.append(segment)
                print("Added final segment. Total segments: \(segments.count)")  // Debug logging
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
    
    private func transcribeVideo(_ videoURL: URL) async throws {
        print("Starting video transcription process for: \(videoURL.path)")
        
        // Get audio duration first
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        print("Video duration: \(duration) seconds")
        
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            print("ERROR: Failed to create speech recognizer")
            throw TranscriptionError.speechRecognizerNotAvailable
        }
        print("Speech recognizer created successfully")
        
        // Check authorization status
        let isAuthorized = await requestSpeechAuthorization()
        print("Speech recognition authorization status: \(isAuthorized)")
        
        guard isAuthorized else {
            print("ERROR: Speech recognition not authorized")
            throw TranscriptionError.notAuthorized
        }
        
        // Verify the file exists and is readable
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("ERROR: Video file does not exist at path: \(videoURL.path)")
            throw TranscriptionError.fileNotFound
        }
        
        let request = SFSpeechURLRecognitionRequest(url: videoURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        
        print("Starting recognition task...")
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self = self else {
                print("ERROR: Self was deallocated")
                continuation.resume(throwing: TranscriptionError.unknown)
                return
            }
            
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    print("ERROR: Recognition task failed with error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else {
                    print("WARNING: No result received from recognition task")
                    return
                }
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // Log each received segment
                    print("Received transcription segment: \(result.bestTranscription.formattedString)")
                    print("Number of segments: \(result.bestTranscription.segments.count)")
                    
                    if let lastSegment = result.bestTranscription.segments.last {
                        let segmentText = lastSegment.substring
                        print("Processing segment: '\(segmentText)'")
                        
                        self.currentBuffer += segmentText
                        if segmentText.last?.isPunctuation == true || segmentText.last?.isWhitespace == true {
                            self.transcription += self.currentBuffer
                            self.currentBuffer = ""
                            print("Updated transcription length: \(self.transcription.count)")
                        }
                        
                        // Update progress - Remove optional binding since timestamp is non-optional
                        let timestamp = lastSegment.timestamp
                        self.progress = min(timestamp / duration, 1.0)
                        print("Progress updated: \(self.progress * 100)%")
                    }
                    
                    if result.isFinal {
                        print("Recognition task completed")
                        print("Final transcription length: \(self.transcription.count)")
                        print("Final transcription: \(self.transcription)")
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    @MainActor
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        let asset = AVURLAsset(url: videoURL)
        
        // Wait for tracks to load
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No audio track found in video"])
        }
        
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
        
        // Add audio mix to ensure we get a valid audio track
        let audioMix = AVMutableAudioMix()
        let audioTrackInput = AVMutableAudioMixInputParameters(track: audioTracks[0])
        audioTrackInput.setVolume(1.0, at: .zero)
        audioMix.inputParameters = [audioTrackInput]
        exportSession.audioMix = audioMix
        
        await exportSession.export()
        
        if let error = exportSession.error {
            throw error
        }
        
        guard exportSession.status == .completed else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Export failed with status: \(exportSession.status.rawValue)"])
        }
        
        // Verify the exported file exists and has content
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: tempURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: tempURL.path),
              (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Exported audio file is invalid or empty"])
        }
        
        return tempURL
    }
    
    private class TranscriptionProgressTracker {
        private let duration: Double
        private var lastProgress: Double = 0
        private var smoothingFactor: Double = 0.1
        private var progressHistory: [Double] = []
        private let historySize = 5
        
        init(duration: Double) {
            self.duration = duration
        }
        
        func update(timestamp: Double) -> Double {
            let rawProgress = min(timestamp / duration, 1.0)
            
            // Add to history
            progressHistory.append(rawProgress)
            if progressHistory.count > historySize {
                progressHistory.removeFirst()
            }
            
            // Calculate moving average
            let avgProgress = progressHistory.reduce(0.0, +) / Double(progressHistory.count)
            
            // Apply smoothing
            lastProgress = (smoothingFactor * avgProgress) + ((1 - smoothingFactor) * lastProgress)
            
            // Ensure progress never decreases
            lastProgress = max(lastProgress, rawProgress)
            
            return lastProgress
        }
    }
    
    private func transcribeAudioFile(_ audioURL: URL, speechRecognizer: SFSpeechRecognizer, duration: Double) async throws {
        guard speechRecognizer.isAvailable else {
            throw NSError(domain: "", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available"])
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        
        let progressTracker = TranscriptionProgressTracker(duration: duration)
        
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self = self else {
                continuation.resume(throwing: NSError(domain: "", code: -1))
                return
            }
            
            print("Starting recognition task for audio at: \(audioURL.path)")
            
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    print("Recognition error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else {
                    print("No result received from recognition task")
                    return
                }
                
                Task { @MainActor in
                    if let lastSegment = result.bestTranscription.segments.last {
                        print("Received segment with text: \(result.bestTranscription.formattedString)")
                        let segment = TranscriptionSegment(
                            text: result.bestTranscription.formattedString,
                            timestamp: lastSegment.timestamp,
                            isFinal: result.isFinal
                        )
                        
                        // Debug logging
                        print("Received transcription segment: \(segment.text)")
                        
                        self?.addSegment(segment)
                        
                        let progress = progressTracker.update(timestamp: lastSegment.timestamp)
                        self?.progress = progress
                        self?.currentSegmentText = segment.text
                        self?.state = .transcribing(
                            progress: progress,
                            currentText: segment.text
                        )
                    }
                    
                    if result.isFinal {
                        print("Final transcription received with text length: \(result.bestTranscription.formattedString.count)")
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
        let downloadedURL = try await YouTubeManager.downloadVideo(from: url) { [weak self] progressLine in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.updateDownloadProgress(progressLine)
            }
        }
        
        // Verify the downloaded file
        guard FileManager.default.fileExists(atPath: downloadedURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: downloadedURL.path),
              (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            throw NSError(domain: "", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Downloaded file is invalid or empty"])
        }
        
        return downloadedURL
    }
    
    @MainActor
    private func updateDownloadProgress(_ progressLine: String) {
        // Improved progress parsing
        let components = progressLine.split(separator: " ")
        var newProgress: Double = self.downloadProgress
        var speed: String?
        var eta: String?
        var size: String?
        
        for (index, component) in components.enumerated() {
            if component.hasSuffix("%") {
                if let percentValue = Double(component.replacingOccurrences(of: "%", with: "")) {
                    // Only update progress if it's actually higher
                    let calculatedProgress = min(percentValue / 100.0, 1.0)
                    if calculatedProgress > self.downloadProgress {
                        withAnimation(.linear(duration: 0.3)) {
                            self.downloadProgress = calculatedProgress
                        }
                    }
                }
            } else if component.hasSuffix("/s") {
                speed = String(component)
            } else if component == "ETA" && index + 1 < components.count {
                eta = "ETA: \(components[index + 1])"
            }
        }
        
        // Only show completed state when actually done
        withAnimation(.easeInOut(duration: 0.3)) {
            self.downloadState = .downloading(
                progress: self.downloadProgress,
                speed: speed,
                eta: eta,
                size: size
            )
        }
    }
    
    private func formatNetworkSpeed(_ speed: String) -> String {
        // Already in a good format (e.g., "2.5MiB/s")
        return speed
    }
    
    private func formatETA(_ eta: String) -> String {
        // Format: "MM:SS" or "HH:MM:SS"
        return "ETA: \(eta)"
    }
    
    private func formatFileSize(_ size: String) -> String {
        // Already in a good format (e.g., "128.45MiB")
        return size
    }
    
    @MainActor
    func handleError(_ message: String) {
        state = .error(message)
    }
    
    @MainActor
    private func checkDependencies() async -> Bool {
        let statuses = await SystemDependencyChecker.checkDependencies()
        let missing = statuses.filter { !$0.isInstalled }
        
        if !missing.isEmpty {
            missingDependencies = missing
            showDependencyAlert = true
            return false
        }
        
        return true
    }
    
    private func withTimeout<T>(of seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "", code: -1, 
                             userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// Add an enum for specific transcription errors
enum TranscriptionError: LocalizedError {
    case speechRecognizerNotAvailable
    case notAuthorized
    case fileNotFound
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .speechRecognizerNotAvailable:
            return "Speech recognizer is not available"
        case .notAuthorized:
            return "Speech recognition is not authorized"
        case .fileNotFound:
            return "Audio file not found"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
