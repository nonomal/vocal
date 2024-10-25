import Foundation

class YouTubeManager {
    enum YouTubeError: Error {
        case invalidURL
        case downloadFailed(String)
        case youtubeDLNotFound
        case setupFailed
    }
    
    private static var youtubeDLPath: String {
        Bundle.main.bundlePath + "/Contents/Resources/youtube-dl"
    }
    
    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        let pattern = #"^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[a-zA-Z0-9_-]{11}.*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex?.firstMatch(in: urlString, range: range) != nil
    }
    
    private static func setupYoutubeDL() async throws {
        // Check if youtube-dl exists in our bundle
        guard FileManager.default.fileExists(atPath: youtubeDLPath) else {
            throw YouTubeError.youtubeDLNotFound
        }
        
        // Make it executable
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", youtubeDLPath]
        
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
        // First ensure youtube-dl is setup
        try await setupYoutubeDL()
        
        // Create temporary directory for download
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Setup youtube-dl process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: youtubeDLPath)
        
        let outputPath = tempDir.appendingPathComponent("video.mp4").path
        process.arguments = [
            url,
            "--format", "best[ext=mp4]",
            "-o", outputPath,
            "--no-playlist",
            "--no-warnings"
        ]
        
        // Setup pipe for output
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        // Handle output in real-time
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async {
                    progressCallback(line)
                }
            }
        }
        
        // Run download process
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0,
              let videoURL = try FileManager.default
                .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .first else {
            throw YouTubeError.downloadFailed("Download failed with status: \(process.terminationStatus)")
        }
        
        return videoURL
    }
}
