import Foundation
import OSLog

/// Manages YouTube video downloads and dependency management
class YouTubeManager {
    // MARK: - Error Types
    
    enum YouTubeError: Error, LocalizedError {
        case invalidURL
        case downloadFailed(String)
        case ytDlpNotFound
        case setupFailed
        case permissionDenied
        case pythonNotFound
        case timeout
        case fileVerificationFailed
        case embeddedResourceMissing
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: 
                return "Invalid YouTube URL. Please check the URL and try again."
            case .downloadFailed(let reason): 
                return "Download failed: \(reason)"
            case .ytDlpNotFound: 
                return "The YouTube downloader tool couldn't be found. Vocal will attempt to set it up automatically."
            case .setupFailed: 
                return "Failed to set up the download process. Please try again or contact support."
            case .permissionDenied: 
                return "Permission denied. Please check your security settings and try again."
            case .pythonNotFound: 
                return "Python not found. Vocal will attempt to use the embedded version."
            case .timeout: 
                return "The download process timed out. This might be due to a slow internet connection or server issues."
            case .fileVerificationFailed: 
                return "The downloaded file couldn't be verified. Please try again."
            case .embeddedResourceMissing:
                return "An embedded resource is missing. Please reinstall the application."
            }
        }
    }
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: "me.nuanc.Vocal", category: "YouTubeManager")
    private static let resourcesDirectory = Bundle.main.resourceURL?.appendingPathComponent("Resources")
    private static let embeddedYtDlpPath = Bundle.main.resourceURL?.appendingPathComponent("Resources/yt-dlp")
    private static let embeddedFfmpegPath = Bundle.main.resourceURL?.appendingPathComponent("Resources/ffmpeg")
    private static let downloadTimeoutSeconds: TimeInterval = 600 // 10 minute timeout
    private static let maxRetryAttempts = 3
    
    // MARK: - Public Methods
    
    /// Downloads a video from YouTube with progress updates
    /// - Parameters:
    ///   - url: The YouTube URL to download
    ///   - progressCallback: Callback for download progress updates
    /// - Returns: URL to the downloaded audio file
    static func downloadVideo(from url: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        logger.info("Starting download for YouTube URL: \(url)")
        
        // Ensure YouTube URL is valid
        guard isValidYouTubeURL(url) else {
            logger.error("Invalid YouTube URL: \(url)")
            throw YouTubeError.invalidURL
        }
        
        // Try to find yt-dlp, first checking embedded resources, then system paths
        let ytDlpPath = try await findOrSetupYtDlp()
        logger.info("Using yt-dlp at path: \(ytDlpPath)")
        
        // Create a unique output directory
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocalDownloads")
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            logger.info("Created output directory: \(outputDir.path)")
        } catch {
            logger.error("Failed to create output directory: \(error.localizedDescription)")
            throw YouTubeError.setupFailed
        }
        
        let outputPath = outputDir.appendingPathComponent("audio").path
        
        // Implement retry logic for download
        var lastError: Error?
        for attempt in 1...maxRetryAttempts {
            do {
                return try await withThrowingTaskGroup(of: URL.self) { group in
                    // Add download task
                    group.addTask {
                        try await downloadWithProgress(
                            url: url,
                            ytDlpPath: ytDlpPath,
                            outputPath: outputPath,
                            progressCallback: { progressLine in
                                // Add attempt number to progress if not the first attempt
                                let message = attempt > 1 ? "Attempt \(attempt): \(progressLine)" : progressLine
                                progressCallback(message)
                            }
                        )
                    }
                    
                    // Add timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(downloadTimeoutSeconds * 1_000_000_000))
                        logger.warning("Download operation timed out after \(downloadTimeoutSeconds) seconds")
                        throw YouTubeError.timeout
                    }
                    
                    // Wait for first completion
                    do {
                        let result = try await group.next()!
                        group.cancelAll()
                        logger.info("Download completed successfully: \(result.path)")
                        return result
                    } catch {
                        logger.error("Download failed with error: \(error.localizedDescription)")
                        group.cancelAll()
                        throw error
                    }
                }
            } catch {
                lastError = error
                logger.warning("Download attempt \(attempt) failed: \(error.localizedDescription). Retrying if attempts remain.")
                
                // If not the last attempt, wait before retrying
                if attempt < maxRetryAttempts {
                    // Exponential backoff: 2, 4, 8 seconds...
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        // If we reached here, all attempts failed
        logger.error("All \(maxRetryAttempts) download attempts failed")
        throw lastError ?? YouTubeError.downloadFailed("All download attempts failed")
    }
    
    // MARK: - Private Methods
    
    /// Attempts to find yt-dlp or set it up if not found
    private static func findOrSetupYtDlp() async throws -> String {
        // First check if we have embedded yt-dlp that's executable
        if let embeddedPath = embeddedYtDlpPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath),
           FileManager.default.isExecutableFile(atPath: embeddedPath) {
            logger.info("Using embedded executable yt-dlp at: \(embeddedPath)")
            
            // Verify the executable works by running a simple command
            if await isToolExecutableAndWorking(path: embeddedPath, testArg: "--version") {
                return embeddedPath
            } else {
                logger.warning("Embedded yt-dlp exists but fails to execute properly. Will try alternative methods.")
            }
        }
        
        // If embedded yt-dlp exists but isn't executable, make it executable
        if let embeddedPath = embeddedYtDlpPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath) {
            try makeFileExecutable(at: embeddedPath)
            logger.info("Made embedded yt-dlp executable at: \(embeddedPath)")
            
            // Verify it works after making executable
            if await isToolExecutableAndWorking(path: embeddedPath, testArg: "--version") {
                return embeddedPath
            } else {
                logger.warning("Made embedded yt-dlp executable but it still fails to run properly")
            }
        }
        
        // Then check system paths
        let systemPaths = [
            "/usr/local/bin/yt-dlp", 
            "/opt/homebrew/bin/yt-dlp",
            "/opt/homebrew/Cellar/yt-dlp/latest/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        
        for path in systemPaths where FileManager.default.fileExists(atPath: path) {
            if await isToolExecutableAndWorking(path: path, testArg: "--version") {
                logger.info("Found working system yt-dlp at: \(path)")
                return path
            }
        }
        
        // If not found, try to extract embedded version
        if let resourcesDir = resourcesDirectory?.path,
           let embeddedZipPath = Bundle.main.path(forResource: "yt-dlp", ofType: "zip") {
            logger.info("Attempting to extract embedded yt-dlp from: \(embeddedZipPath)")
            
            // Create resources directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: resourcesDir) {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: resourcesDir), withIntermediateDirectories: true)
                logger.info("Created resources directory: \(resourcesDir)")
            }
            
            // Extract and make executable
            let extractedPath = try await extractAndSetupTool(from: embeddedZipPath, to: resourcesDir, name: "yt-dlp")
            logger.info("Successfully extracted yt-dlp to: \(extractedPath)")
            
            // Verify it works after extraction
            if await isToolExecutableAndWorking(path: extractedPath, testArg: "--version") {
                return extractedPath
            } else {
                logger.warning("Extracted yt-dlp but it fails to run properly")
            }
        }
        
        logger.error("yt-dlp not found and couldn't be set up")
        throw YouTubeError.ytDlpNotFound
    }
    
    /// Tests if a tool can be executed and returns expected output
    private static func isToolExecutableAndWorking(path: String, testArg: String) async -> Bool {
        logger.debug("Testing if tool is executable and working: \(path)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [testArg]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let outputData = try? outputPipe.fileHandleForReading.readToEnd()
                let output = outputData.flatMap { String(data: $0, encoding: .utf8) }
                
                // For most tools, non-empty output on a simple version check indicates it's working
                let isWorking = (output?.isEmpty == false)
                logger.debug("Tool at \(path) working status: \(isWorking)")
                return isWorking
            } else {
                let errorData = try? errorPipe.fileHandleForReading.readToEnd()
                let errorMessage = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                logger.warning("Tool at \(path) failed with status \(process.terminationStatus): \(errorMessage)")
                return false
            }
        } catch {
            logger.warning("Failed to execute tool at \(path): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Makes a file executable
    private static func makeFileExecutable(at path: String) throws {
        logger.info("Making file executable: \(path)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", path]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = try errorPipe.fileHandleForReading.readToEnd()
                let errorMessage = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                logger.error("Failed to make file executable: \(path), error: \(errorMessage)")
                throw YouTubeError.setupFailed
            }
            
            logger.info("Successfully made file executable: \(path)")
        } catch {
            logger.error("Error making file executable: \(error.localizedDescription)")
            throw YouTubeError.setupFailed
        }
    }
    
    /// Extracts a tool from a zip file and makes it executable
    private static func extractAndSetupTool(from zipPath: String, to directory: String, name: String) async throws -> String {
        logger.info("Extracting \(name) from \(zipPath) to \(directory)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipPath, "-d", directory]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = try errorPipe.fileHandleForReading.readToEnd()
                let errorMessage = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                logger.error("Failed to extract \(name) from zip: \(errorMessage)")
                throw YouTubeError.setupFailed
            }
            
            let extractedPath = "\(directory)/\(name)"
            
            // Verify the file was extracted
            guard FileManager.default.fileExists(atPath: extractedPath) else {
                logger.error("Extraction succeeded but file not found at \(extractedPath)")
                throw YouTubeError.fileVerificationFailed
            }
            
            try makeFileExecutable(at: extractedPath)
            logger.info("Successfully extracted and made executable: \(extractedPath)")
            return extractedPath
        } catch {
            logger.error("Error extracting \(name): \(error.localizedDescription)")
            throw YouTubeError.setupFailed
        }
    }
    
    /// Downloads a YouTube video with progress tracking
    private static func downloadWithProgress(
        url: String,
        ytDlpPath: String,
        outputPath: String,
        progressCallback: @escaping (String) -> Void
    ) async throws -> URL {
        let originalURL = URL(fileURLWithPath: outputPath)
        let audioURL = originalURL.appendingPathExtension("m4a")
        
        // Create output directory if it doesn't exist
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Find ffmpeg path
        let ffmpegPath = try await findFfmpegPath()
        logger.info("Using ffmpeg at path: \(ffmpegPath)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        
        // Use a more reliable set of options
        process.arguments = [
            url,
            "--format", "bestaudio[ext=m4a]/bestaudio/best",
            "-o", outputPath,
            "--no-playlist",
            "--extract-audio",
            "--audio-format", "m4a",
            "--audio-quality", "0",
            "--progress",
            "--newline",
            "--no-cache-dir",
            "--force-overwrites",
            "--prefer-ffmpeg",
            "--ffmpeg-location", ffmpegPath,
            "--no-check-certificate", // Avoid SSL issues
            "--verbose",
            "--no-part",              // Don't use .part files to avoid permission issues
            "--retries", "3",         // Built-in retry for network issues
            "--fragment-retries", "3" // Built-in retry for segment downloads
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            logger.info("Started yt-dlp process with arguments: \(process.arguments?.joined(separator: " ") ?? "")")
            
            // Handle output in real-time with more detailed logging
            Task {
                for try await line in outputPipe.fileHandleForReading.bytes.lines {
                    progressCallback(line)
                    
                    // More detailed logging of progress
                    if line.contains("%") {
                        logger.debug("Download progress: \(line)")
                    } else {
                        logger.debug("yt-dlp output: \(line)")
                    }
                }
            }
            
            // Collect error output
            var errorLines: [String] = []
            Task {
                for try await line in errorPipe.fileHandleForReading.bytes.lines {
                    errorLines.append(line)
                    logger.warning("yt-dlp error: \(line)")
                }
            }
            
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Check for the .m4a file since yt-dlp converts and removes the original
                guard FileManager.default.fileExists(atPath: audioURL.path),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
                      (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
                    logger.error("File verification failed at path: \(audioURL.path)")
                    throw YouTubeError.fileVerificationFailed
                }
                
                logger.info("Successfully downloaded file to: \(audioURL.path)")
                logger.info("File size: \((attributes[.size] as? NSNumber)?.intValue ?? 0) bytes")
                return audioURL
            } else {
                let errorOutput = errorLines.joined(separator: "\n")
                logger.error("Download process failed with status \(process.terminationStatus): \(errorOutput)")
                
                // Provide more detailed and specific error messages
                if errorOutput.contains("Permission denied") {
                    throw YouTubeError.permissionDenied
                } else if errorOutput.contains("HTTP Error 429") {
                    throw YouTubeError.downloadFailed("YouTube is rate limiting downloads. Please try again later.")
                } else if errorOutput.contains("This video is only available for registered users") {
                    throw YouTubeError.downloadFailed("This video requires authentication and cannot be downloaded.")
                } else if errorOutput.contains("Video unavailable") {
                    throw YouTubeError.downloadFailed("This video is unavailable. It may be private or removed.")
                } else if errorOutput.contains("Unsupported URL") {
                    throw YouTubeError.downloadFailed("YouTube URL format not supported. Please try a standard YouTube video URL.")
                } else if errorOutput.contains("Unable to extract") {
                    throw YouTubeError.downloadFailed("Unable to extract video information. YouTube may have changed their format.")
                } else if errorOutput.contains("No internet connection") || errorOutput.contains("urlopen error") {
                    throw YouTubeError.downloadFailed("Network error. Please check your internet connection and try again.")
                } else {
                    throw YouTubeError.downloadFailed("Download failed. Please check your internet connection and try again.")
                }
            }
        } catch let error as YouTubeError {
            logger.error("YouTube error: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Download process error: \(error.localizedDescription)")
            throw YouTubeError.downloadFailed(error.localizedDescription)
        }
    }
    
    /// Finds the ffmpeg path or uses embedded version
    private static func findFfmpegPath() async throws -> String {
        // First check if we have embedded ffmpeg that's executable
        if let embeddedPath = embeddedFfmpegPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath),
           FileManager.default.isExecutableFile(atPath: embeddedPath) {
            logger.info("Using embedded executable ffmpeg at: \(embeddedPath)")
            
            // Verify the executable works
            if await isToolExecutableAndWorking(path: embeddedPath, testArg: "-version") {
                return embeddedPath
            } else {
                logger.warning("Embedded ffmpeg exists but fails to execute properly")
            }
        }
        
        // If embedded ffmpeg exists but isn't executable, make it executable
        if let embeddedPath = embeddedFfmpegPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath) {
            try makeFileExecutable(at: embeddedPath)
            logger.info("Made embedded ffmpeg executable at: \(embeddedPath)")
            
            // Verify it works after making executable
            if await isToolExecutableAndWorking(path: embeddedPath, testArg: "-version") {
                return embeddedPath
            } else {
                logger.warning("Made embedded ffmpeg executable but it still fails to run properly")
            }
        }
        
        // Then check system paths
        let systemPaths = [
            "/usr/local/bin/ffmpeg", 
            "/opt/homebrew/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        
        for path in systemPaths where FileManager.default.fileExists(atPath: path) {
            if await isToolExecutableAndWorking(path: path, testArg: "-version") {
                logger.info("Found working system ffmpeg at: \(path)")
                return path
            }
        }
        
        // If not found, try to extract embedded version
        if let resourcesDir = resourcesDirectory?.path,
           let embeddedZipPath = Bundle.main.path(forResource: "ffmpeg", ofType: "zip") {
            logger.info("Attempting to extract embedded ffmpeg from: \(embeddedZipPath)")
            
            // Create resources directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: resourcesDir) {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: resourcesDir), withIntermediateDirectories: true)
                logger.info("Created resources directory: \(resourcesDir)")
            }
            
            // Extract and make executable
            let extractedPath = try await extractAndSetupTool(from: embeddedZipPath, to: resourcesDir, name: "ffmpeg")
            logger.info("Successfully extracted ffmpeg to: \(extractedPath)")
            
            // Verify it works after extraction
            if await isToolExecutableAndWorking(path: extractedPath, testArg: "-version") {
                return extractedPath
            } else {
                logger.warning("Extracted ffmpeg but it fails to run properly")
            }
        }
        
        logger.error("ffmpeg not found and couldn't be set up")
        throw YouTubeError.setupFailed
    }
    
    /// Validates if a string is a valid YouTube URL
    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        let pattern = #"^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[a-zA-Z0-9_-]{11}.*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex?.firstMatch(in: urlString, range: range) != nil
    }
    
    /// Attempts to repair the YouTube download setup
    static func repairSetup() async throws {
        logger.info("Attempting to repair YouTube download setup")
        
        // Clear any existing resources
        if let resourcesDir = resourcesDirectory {
            // Only remove yt-dlp and ffmpeg files, not the entire directory
            let ytDlpPath = resourcesDir.appendingPathComponent("yt-dlp")
            let ffmpegPath = resourcesDir.appendingPathComponent("ffmpeg")
            
            try? FileManager.default.removeItem(at: ytDlpPath)
            try? FileManager.default.removeItem(at: ffmpegPath)
            
            // Ensure the directory exists
            if !FileManager.default.fileExists(atPath: resourcesDir.path) {
                try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
            }
        }
        
        // Re-extract tools
        do {
            _ = try await findOrSetupYtDlp()
            _ = try await findFfmpegPath()
            
            logger.info("YouTube download setup repair completed successfully")
        } catch {
            logger.error("Failed to repair YouTube download setup: \(error.localizedDescription)")
            throw error
        }
    }
}
