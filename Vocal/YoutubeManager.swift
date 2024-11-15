import Foundation

class YouTubeManager {
    enum YouTubeError: Error {
        case invalidURL
        case downloadFailed(String)
        case ytDlpNotFound
        case setupFailed
        case permissionDenied
        case pythonNotFound
    }
    
    private static var ytDlpPath: String? {
        // First try to find yt-dlp in the system
        let systemPaths = [
            "/usr/local/bin/yt-dlp",
            "/opt/homebrew/bin/yt-dlp"
        ]
        
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Fall back to the bundled version
        if let resourcePath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            return resourcePath
        }
        return nil
    }
    
    private static func findPython() throws -> String {
        let pythonPaths = [
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3"
        ]
        
        for path in pythonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        throw YouTubeError.pythonNotFound
    }
    
    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        let pattern = #"^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[a-zA-Z0-9_-]{11}.*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex?.firstMatch(in: urlString, range: range) != nil
    }
    
    static func downloadVideo(from url: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        // Ensure we have yt-dlp
        guard let ytDlpPath = ytDlpPath else {
            throw YouTubeError.ytDlpNotFound
        }
        
        // Find Python interpreter
        let pythonPath = try findPython()
        
        // Create temporary directory in the app's container
        let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tempDir = containerURL.appendingPathComponent("Downloads").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let outputPath = tempDir.appendingPathComponent("video.mp4").path
        
        // Create a temporary script file
        let scriptPath = tempDir.appendingPathComponent("download_script.py")
        let scriptContent = """
        #!/usr/bin/env python3
        # -*- coding: utf-8 -*-
        import sys
        import subprocess
        
        def main():
            try:
                cmd = [
                    '\(ytDlpPath)',
                    '\(url)',
                    '--format', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
                    '-o', '\(outputPath)',
                    '--no-playlist',
                    '--no-warnings',
                    '--no-cache-dir',
                    '--force-overwrites'
                ]
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.stderr:
                    print(result.stderr, file=sys.stderr)
                if result.stdout:
                    print(result.stdout)
                sys.exit(result.returncode)
            except Exception as e:
                print(f"Error: {str(e)}", file=sys.stderr)
                sys.exit(1)
        
        if __name__ == '__main__':
            main()
        """
        
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath.path]
        
        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["PYTHONIOENCODING"] = "utf-8"
        env.removeValue(forKey: "PYTHONPATH")
        process.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            if let outputText = String(data: fileHandle.availableData, encoding: .utf8),
               !outputText.isEmpty {
                // Parse progress from the output
                if outputText.contains("%") {
                    progressCallback(outputText)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            if let errorText = String(data: fileHandle.availableData, encoding: .utf8), 
               !errorText.isEmpty {
                print("yt-dlp Error: \(errorText)")
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
        
        // Verify the video file exists
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw YouTubeError.downloadFailed("Downloaded file not found")
        }
        
        // Clean up the script file
        try? FileManager.default.removeItem(at: scriptPath)
        
        return URL(fileURLWithPath: outputPath)
    }
}
