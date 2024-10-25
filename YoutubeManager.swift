import Foundation

class YouTubeManager {
    enum YouTubeError: Error {
        case invalidURL
        case downloadFailed(String)
        case ytDlpNotFound
        case setupFailed
        case permissionDenied
    }
    
    private static var ytDlpPath: String {
        if let resourcePath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            return resourcePath
        }
        return Bundle.main.bundlePath + "/Contents/Resources/yt-dlp"
    }
    
    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        let pattern = #"^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[a-zA-Z0-9_-]{11}.*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex?.firstMatch(in: urlString, range: range) != nil
    }
    
    private static func setupYtDlp() async throws {
        guard FileManager.default.fileExists(atPath: ytDlpPath) else {
            throw YouTubeError.ytDlpNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", ytDlpPath]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                throw YouTubeError.setupFailed
            }
        } catch {
            throw YouTubeError.setupFailed
        }
    }
    
    static func downloadVideo(from url: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        try await setupYtDlp()
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        
        let outputPath = tempDir.appendingPathComponent("video.mp4").path
        process.arguments = [
            url,
            "--format", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "-o", outputPath,
            "--no-playlist",
            "--no-warnings",
            "--no-cache-dir"
        ]
        
        process.currentDirectoryURL = tempDir
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async {
                    progressCallback(line)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                print("yt-dlp Error: \(line)")
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw YouTubeError.downloadFailed("Failed to start download process: \(error.localizedDescription)")
        }
        
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        
        guard process.terminationStatus == 0 else {
            throw YouTubeError.downloadFailed("Download failed with status: \(process.terminationStatus)")
        }
        
        let expectedVideoURL = tempDir.appendingPathComponent("video.mp4")
        guard FileManager.default.fileExists(atPath: expectedVideoURL.path) else {
            throw YouTubeError.downloadFailed("Downloaded file not found")
        }
        
        return expectedVideoURL
    }
}
