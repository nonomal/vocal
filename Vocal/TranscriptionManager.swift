import Foundation
import Speech
import SwiftUI
import OSLog
import ObjectiveC

enum TranscriptionState {
    case idle
    case checkingDependencies
    case downloading(progress: Double, speed: String?, eta: String?, size: String?)
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
    private static let logger = Logger(subsystem: "me.nuanc.Vocal", category: "TranscriptionManager")
    
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
        // Cancel any ongoing recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Use a detached task to clean up temp files without capturing self
        let tempFilePaths = tempFiles.map { $0.path }
        Task.detached {
            for path in tempFilePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
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
        Self.logger.info("Requesting speech recognition authorization")
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Self.logger.info("Speech recognition authorization status: \(status.rawValue)")
                switch status {
                case .authorized:
                    Self.logger.info("Speech recognition authorized")
                case .denied:
                    Self.logger.warning("Speech recognition denied")
                case .restricted:
                    Self.logger.warning("Speech recognition restricted")
                case .notDetermined:
                    Self.logger.warning("Speech recognition not determined")
                @unknown default:
                    Self.logger.warning("Speech recognition unknown status")
                }
                continuation.resumeIfNotResolved(returning: status)
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
                    return await dependencyTask.value
                }
                
                guard hasRequirements else { return }
                
                state = .preparingAudio(progress: 0)
                videoURL = url
                
                guard await requestSpeechAuthorization() else {
                    throw NSError(domain: "", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Speech recognition authorization denied. Please enable it in System Settings > Privacy & Security > Speech Recognition."])
                }
                
                resetTranscription()
                try await transcribeVideo(url)
                finalizeTranscription()
                state = .completed
            } catch {
                state = .error(error.localizedDescription)
                Self.logger.error("Transcription error: \(error.localizedDescription)")
            }
        }
    }
    
    func handleYouTubeURL(_ urlString: String) {
        Task {
            do {
                await MainActor.run { self.state = .checkingDependencies }
                
                // Validate YouTube URL first
                guard YouTubeManager.isValidYouTubeURL(urlString) else {
                    await MainActor.run { 
                        self.state = .error("Invalid YouTube URL. Please check the URL and try again.") 
                    }
                    return
                }
                
                Self.logger.info("Starting YouTube transcription process for: \(urlString)")
                
                // Ensure speech recognition is authorized before downloading
                guard await requestSpeechAuthorization() else {
                    throw NSError(domain: "", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Speech recognition authorization denied. Please enable it in System Settings > Privacy & Security > Speech Recognition."])
                }
                
                // Check dependencies with timeout
                let dependencyTask = Task {
                    return await checkDependencies()
                }
                
                let hasRequirements = try await withTimeout(of: 10) {
                    try await dependencyTask.value
                }
                
                // If missing dependencies, try to set them up automatically
                if !hasRequirements {
                    Self.logger.info("Missing dependencies. Attempting automatic setup.")
                    
                    await MainActor.run {
                        self.state = .downloading(progress: 0, speed: nil, eta: "Setting up dependencies...", size: nil)
                    }
                    
                    let setupSuccess = await SystemDependencyChecker.setupMissingDependencies()
                    if !setupSuccess {
                        Self.logger.warning("Automatic dependency setup failed.")
                        await MainActor.run {
                            self.state = .error("Failed to set up required tools. Please use the 'Repair YouTube Setup' option.")
                        }
                        return
                    }
                    Self.logger.info("Automatic dependency setup succeeded.")
                }
                
                await MainActor.run {
                    self.resetTranscription()
                    self.downloadState = .downloading(progress: 0, speed: nil, eta: "Starting download...", size: nil)
                    self.state = .downloading(progress: 0, speed: nil, eta: "Starting download...", size: nil)
                }
                
                // Download the YouTube video with improved error handling
                Self.logger.info("Starting YouTube download for: \(urlString)")
                let videoURL = try await downloadYouTubeVideo(urlString)
                
                await MainActor.run {
                    self.tempFiles.append(videoURL)
                    self.state = .preparingAudio(progress: 0)
                    self.downloadState = .completed
                }
                
                Self.logger.info("Starting transcription of downloaded video: \(videoURL.path)")
                try await transcribeVideo(videoURL)
                
                await MainActor.run {
                    self.finalizeTranscription()
                    self.state = .completed
                    self.downloadState = .idle
                }
            } catch {
                Self.logger.error("YouTube download/transcription error: \(error.localizedDescription)")
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                    self.downloadState = .idle
                }
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
        Self.logger.debug("Adding segment: \(segment.text)")
        
        if self.segments.last?.text != segment.text {
            if segment.isFinal {
                self.segments.append(segment)
                Self.logger.debug("Added final segment. Total segments: \(self.segments.count)")
            }
        }
        
        formatAndPublishTranscription()
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
        Self.logger.info("Final transcription length: \(self.transcription.count) characters")
        
        // Calculate word count and reading time
        let words = transcription.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        wordCount = words.count
        estimatedReadingTime = Double(wordCount) / wordsPerMinute * 60
    }
    
    private func transcribeVideo(_ videoURL: URL) async throws {
        Self.logger.info("Starting video transcription process for: \(videoURL.path)")
        
        // Get audio duration first
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        Self.logger.info("Video duration: \(duration) seconds")
        
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            Self.logger.error("Failed to create speech recognizer")
            throw TranscriptionError.speechRecognizerNotAvailable
        }
        Self.logger.info("Speech recognizer created successfully")
        
        // Verify the file exists and is readable
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            Self.logger.error("Video file does not exist at path: \(videoURL.path)")
            throw TranscriptionError.fileNotFound
        }
        
        let request = SFSpeechURLRecognitionRequest(url: videoURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        
        Self.logger.info("Starting recognition task...")
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self = self else {
                Self.logger.error("Self was deallocated")
                continuation.resumeIfNotResolved(throwing: TranscriptionError.unknown)
                return
            }
            
            // Set a timeout for the recognition task
            let timeoutTask = Task { 
                do {
                    // Use a relative timeout based on audio duration, but set a max of 30 minutes
                    let timeoutDuration = min(max(duration * 1.5, 30), 30 * 60)  // in seconds
                    try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                    // If we're still running after timeout, cancel and resume
                    if self.recognitionTask != nil {
                        Self.logger.warning("Recognition task timed out, cancelling")
                        await MainActor.run {
                            self.cancellRecognitionTask()
                            // Don't throw an error, just end gracefully with whatever we have
                            if !continuation.isResolved {
                                continuation.resumeIfNotResolved()
                            }
                        }
                    }
                } catch {
                    // Task was cancelled, which is fine
                }
            }
            
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    Self.logger.error("Recognition task failed with error: \(error.localizedDescription)")
                    // Cancel the timeout task
                    timeoutTask.cancel()
                    if !continuation.isResolved {
                        continuation.resumeIfNotResolved(throwing: error)
                    }
                    return
                }
                
                guard let result = result else {
                    Self.logger.warning("No result received from recognition task")
                    return
                }
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // Update progress
                    let calculatedProgress = min((result.bestTranscription.segments.last?.timestamp ?? 0) / duration, 1.0)
                    self.progress = calculatedProgress
                    
                    let segmentText = result.bestTranscription.formattedString
                    self.currentSegmentText = segmentText
                    
                    // Log progress periodically
                    if Int(calculatedProgress * 100) % 10 == 0 {
                        Self.logger.debug("Transcription progress: \(Int(calculatedProgress * 100))%, text length: \(segmentText.count)")
                    }
                    
                    // Add as segment if it's final or we've reached the end
                    if result.isFinal {
                        self.addSegment(TranscriptionSegment(
                            text: segmentText,
                            timestamp: result.bestTranscription.segments.last?.timestamp ?? 0,
                            isFinal: true
                        ))
                        
                        // If we're done, complete the continuation
                        if calculatedProgress >= 0.99 || result.isFinal {
                            self.cancellRecognitionTask()
                            // Cancel the timeout task
                            timeoutTask.cancel()
                            Self.logger.info("Transcription completed successfully")
                            if !continuation.isResolved {
                                continuation.resumeIfNotResolved()
                            }
                        }
                    }
                    
                    // Update state
                    self.state = .transcribing(progress: self.progress, currentText: segmentText)
                }
            }
        }
    }
    
    @MainActor
    private func cancellRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    private func downloadYouTubeVideo(_ url: String) async throws -> URL {
        await MainActor.run {
            self.downloadState = .downloading(progress: 0, speed: nil, eta: "Initializing...", size: nil)
        }
        
        do {
            // Use the improved YouTubeManager to download the video
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
                             userInfo: [NSLocalizedDescriptionKey: "Downloaded file is invalid or empty. Please try again."])
            }
            
            return downloadedURL
        } catch {
            // If the download fails due to missing dependencies, try to repair the setup
            if let ytError = error as? YouTubeManager.YouTubeError {
                switch ytError {
                case .ytDlpNotFound, .setupFailed, .embeddedResourceMissing:
                    // Try to repair the setup
                    Self.logger.info("Download failed due to dependency issues. Attempting repair.")
                    await MainActor.run {
                        self.downloadState = .downloading(progress: 0, speed: nil, 
                                                          eta: "Repairing YouTube setup...", size: nil)
                    }
                    
                    do {
                        try await YouTubeManager.repairSetup()
                        // Try the download again
                        Self.logger.info("Retrying download after repair")
                        
                        await MainActor.run {
                            self.downloadState = .downloading(progress: 0, speed: nil, 
                                                             eta: "Restarting download...", size: nil)
                        }
                        
                        return try await YouTubeManager.downloadVideo(from: url) { [weak self] progressLine in
                            guard let self = self else { return }
                            
                            Task { @MainActor in
                                self.updateDownloadProgress(progressLine)
                            }
                        }
                    } catch {
                        // If repair fails, throw a more user-friendly error
                        Self.logger.error("Repair failed: \(error.localizedDescription)")
                        throw NSError(domain: "", code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "Failed to set up YouTube download tools. Please try the 'Repair YouTube Setup' option to fix this issue."])
                    }
                case .timeout:
                    throw NSError(domain: "", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "The download timed out. YouTube might be slow or the video might be too large. Please try again or try a shorter video."])
                case .fileVerificationFailed:
                    throw NSError(domain: "", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "The downloaded file couldn't be verified. Please try again or try another video."])
                default:
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    @MainActor
    private func updateDownloadProgress(_ progressLine: String) {
        // Improved progress parsing
        let components = progressLine.split(separator: " ")
        var speed: String?
        var eta: String?
        var size: String?
        var progress: Double? = nil
        
        for (index, component) in components.enumerated() {
            if component.hasSuffix("%") {
                if let percentValue = Double(component.replacingOccurrences(of: "%", with: "")) {
                    // Update progress value
                    progress = min(percentValue / 100.0, 1.0)
                }
            } else if component.hasSuffix("/s") {
                speed = String(component)
            } else if component == "ETA" && index + 1 < components.count {
                eta = "ETA: \(components[index + 1])"
            } else if component == "of" && index + 1 < components.count {
                if components[index + 1].hasSuffix("iB") { // Check if it's a size indicator (MiB, GiB, etc.)
                    size = String(components[index + 1])
                }
            }
        }
        
        // Update state with new progress info
        if let progress = progress {
            // Only update progress if it's actually higher
            if progress > self.downloadProgress {
                withAnimation(.linear(duration: 0.3)) {
                    self.downloadProgress = progress
                }
            }
        }
        
        // Create a more user-friendly status message
        var statusMessage = "Downloading..."
        if let speedValue = speed {
            statusMessage = "Downloading at \(speedValue)"
        }
        
        if progressLine.contains("Destination") {
            statusMessage = "Preparing download..."
        } else if progressLine.contains("Extracting audio") {
            statusMessage = "Extracting audio..."
        } else if progressLine.contains("Writing metadata") {
            statusMessage = "Finalizing..."
        } else if progressLine.contains("Deleting") {
            statusMessage = "Cleaning up..."
        }
        
        // Only show completed state when actually done
        withAnimation(.easeInOut(duration: 0.3)) {
            self.downloadState = .downloading(
                progress: self.downloadProgress,
                speed: speed,
                eta: eta ?? statusMessage,
                size: size
            )
            
            // Also update the main state if we're in downloading state
            if case .downloading = self.state {
                self.state = .downloading(
                    progress: self.downloadProgress,
                    speed: speed,
                    eta: eta ?? statusMessage,
                    size: size
                )
            }
        }
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
    
    func repairYouTubeSetup() async -> Bool {
        do {
            try await YouTubeManager.repairSetup()
            return true
        } catch {
            Self.logger.error("Failed to repair YouTube setup: \(error.localizedDescription)")
            return false
        }
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
    
    func clearContent() {
        transcription = ""
        videoURL = nil
        state = .idle
        downloadState = .idle
        segments = []
        wordCount = 0
        estimatedReadingTime = 0
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
            return "Speech recognition is not authorized. Please enable it in System Settings > Privacy & Security > Speech Recognition."
        case .fileNotFound:
            return "Audio file not found"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// Reference type to track resolution state
private class ResolutionState {
    var isResolved = false
}

// Extension to track continuation resolution
private var continuationKey: UInt8 = 0

extension CheckedContinuation {
    // Use associated object to track whether continuation has been resolved
    private var resolutionState: ResolutionState {
        get {
            if let state = objc_getAssociatedObject(self, &continuationKey) as? ResolutionState {
                return state
            }
            let state = ResolutionState()
            objc_setAssociatedObject(self, &continuationKey, state, .OBJC_ASSOCIATION_RETAIN)
            return state
        }
    }
    
    var isResolved: Bool {
        return resolutionState.isResolved
    }
    
    // Non-mutating methods that work with any CheckedContinuation
    func resumeIfNotResolved() where T == Void {
        guard !resolutionState.isResolved else { return }
        resolutionState.isResolved = true
        resume()
    }
    
    func resumeIfNotResolved(throwing error: E) {
        guard !resolutionState.isResolved else { return }
        resolutionState.isResolved = true
        resume(throwing: error)
    }
    
    func resumeIfNotResolved(returning value: T) {
        guard !resolutionState.isResolved else { return }
        resolutionState.isResolved = true
        resume(returning: value)
    }
}
