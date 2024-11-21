import Foundation

class YouTubeManager {
    enum YouTubeError: Error, LocalizedError {
        case invalidURL
        case downloadFailed(String)
        case ytDlpNotFound
        case setupFailed
        case permissionDenied
        case pythonNotFound
        case timeout
        case fileVerificationFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid YouTube URL"
            case .downloadFailed(let reason): return "Download failed: \(reason)"
            case .ytDlpNotFound: return "yt-dlp not found. Please install it first."
            case .setupFailed: return "Failed to setup download"
            case .permissionDenied: return "Permission denied"
            case .pythonNotFound: return "Python not found"
            case .timeout: return "Operation timed out"
            case .fileVerificationFailed: return "Downloaded file verification failed"
            }
        }
    }
    
    static func downloadVideo(from url: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        let ytDlpPath = try findYtDlp()
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocalDownloads")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputPath = outputDir.appendingPathComponent("audio").path
        
        return try await withThrowingTaskGroup(of: URL.self) { group in
            // Add download task
            group.addTask {
                try await downloadWithProgress(
                    url: url,
                    ytDlpPath: ytDlpPath,
                    outputPath: outputPath,
                    progressCallback: progressCallback
                )
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(300 * 1_000_000_000)) // 5 minutes
                throw YouTubeError.timeout
            }
            
            // Wait for first completion
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private static func downloadWithProgress(
        url: String,
        ytDlpPath: String,
        outputPath: String,
        progressCallback: @escaping (String) -> Void
    ) async throws -> URL {
        let originalURL = URL(fileURLWithPath: outputPath)
        let audioURL = originalURL.appendingPathExtension("m4a")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        
        // Create output directory if it doesn't exist
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
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
            "--ffmpeg-location", "/opt/homebrew/bin/ffmpeg",
            "--verbose"
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Handle output in real-time
            Task {
                for try await line in outputPipe.fileHandleForReading.bytes.lines {
                    progressCallback(line)
                    print("yt-dlp output: \(line)")  // Debug logging
                }
            }
            
            // Handle error output in real-time
            Task {
                for try await line in errorPipe.fileHandleForReading.bytes.lines {
                    print("yt-dlp error: \(line)")  // Debug logging
                }
            }
            
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Check for the .m4a file since yt-dlp converts and removes the original
                guard FileManager.default.fileExists(atPath: audioURL.path),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
                      (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
                    print("File verification failed at path: \(audioURL.path)")
                    throw YouTubeError.fileVerificationFailed
                }
                
                print("Successfully downloaded file to: \(audioURL.path)")
                print("File size: \((attributes[.size] as? NSNumber)?.intValue ?? 0) bytes")
                return audioURL
            } else {
                let errorOutput = try errorPipe.fileHandleForReading.readToEnd().flatMap { String(data: $0, encoding: .utf8) }
                throw YouTubeError.downloadFailed("Download process failed with status \(process.terminationStatus): \(errorOutput ?? "No error details")")
            }
        } catch {
            print("Download process error: \(error)")
            throw error
        }
    }
    
    private static func findYtDlp() throws -> String {
        let paths = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        throw YouTubeError.ytDlpNotFound
    }
    
    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        let pattern = #"^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[a-zA-Z0-9_-]{11}.*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex?.firstMatch(in: urlString, range: range) != nil
    }
}
