import Foundation

class SystemDependencyChecker {
    private static let cache = NSCache<NSString, DependencyStatus>()
    private static let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    private static let pythonPaths = [
        "/usr/local/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/bin/python3"
    ]
    
    private static let ytDlpPaths = [
        "/usr/local/bin/yt-dlp",
        "/opt/homebrew/bin/yt-dlp",
        "/opt/homebrew/Cellar/yt-dlp/latest/bin/yt-dlp"
    ]
    
    private static let ffmpegPaths = [
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/bin/ffmpeg"
    ]
    
    static func checkDependencies() async -> [DependencyStatus] {
        // Fast path: check cache first
        if let cachedResults = getCachedResults() {
            return cachedResults
        }
        
        // Run checks with timeout
        if let results = await withTimeout(seconds: 5) { () async throws -> [DependencyStatus] in
            async let pythonStatus = checkPython()
            async let ytDlpStatus = checkYtDlp()
            async let ffmpegStatus = checkFfmpeg()
            return await [pythonStatus, ytDlpStatus, ffmpegStatus]
        } {
            cacheDependencyResults(results)
            return results
        }
        
        return []
    }
    
    private static func getCachedResults() -> [DependencyStatus]? {
        guard let pythonStatus = cache.object(forKey: "python" as NSString),
              let ytDlpStatus = cache.object(forKey: "ytdlp" as NSString),
              let ffmpegStatus = cache.object(forKey: "ffmpeg" as NSString) else {
            return nil
        }
        return [pythonStatus, ytDlpStatus, ffmpegStatus]
    }
    
    private static func cacheDependencyResults(_ results: [DependencyStatus]) {
        cache.setObject(results[0], forKey: "python" as NSString)
        cache.setObject(results[1], forKey: "ytdlp" as NSString)
        cache.setObject(results[2], forKey: "ffmpeg" as NSString)
    }
    
    private static func checkPython() async -> DependencyStatus {
        // First try direct path checking
        for path in pythonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return DependencyStatus(.installed(dependency: .python))
            }
        }
        
        // Fallback to which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return DependencyStatus(.installed(dependency: .python))
            }
        } catch {
            print("Python check error: \(error)")
        }
        
        return DependencyStatus(.missing(
            dependency: .python,
            installCommand: "brew install python3",
            helpURL: "https://www.python.org/downloads/"
        ))
    }
    
    private static func checkYtDlp() async -> DependencyStatus {
        // First try direct path checking
        for path in ytDlpPaths {
            if FileManager.default.fileExists(atPath: path) {
                return DependencyStatus(.installed(dependency: .ytDlp))
            }
        }
        
        // Fallback to which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return DependencyStatus(.installed(dependency: .ytDlp))
            }
        } catch {
            print("yt-dlp check error: \(error)")
        }
        
        return DependencyStatus(.missing(
            dependency: .ytDlp,
            installCommand: "brew install yt-dlp",
            helpURL: "https://github.com/yt-dlp/yt-dlp#installation"
        ))
    }
    
    private static func checkFfmpeg() async -> DependencyStatus {
        // First try direct path checking
        for path in ffmpegPaths {
            if FileManager.default.fileExists(atPath: path) {
                return DependencyStatus(.installed(dependency: .ffmpeg))
            }
        }
        
        // Fallback to which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return DependencyStatus(.installed(dependency: .ffmpeg))
            }
        } catch {
            print("ffmpeg check error: \(error)")
        }
        
        return DependencyStatus(.missing(
            dependency: .ffmpeg,
            installCommand: "brew install ffmpeg",
            helpURL: "https://ffmpeg.org/download.html"
        ))
    }
    
    private static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw TimeoutError()
                }
                
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            print("Operation timed out or failed: \(error)")
            return nil
        }
    }
    
    private struct TimeoutError: Error {}
}

enum SystemDependency: String {
    case python = "Python 3"
    case ytDlp = "yt-dlp"
    case ffmpeg = "FFmpeg"
}

class DependencyStatus {
    let type: StatusType
    
    enum StatusType {
        case installed(dependency: SystemDependency)
        case missing(dependency: SystemDependency, installCommand: String, helpURL: String)
    }
    
    init(_ type: StatusType) {
        self.type = type
    }
    
    var dependency: SystemDependency {
        switch type {
        case .installed(let dep), .missing(let dep, _, _):
            return dep
        }
    }
    
    var isInstalled: Bool {
        if case .installed = type {
            return true
        }
        return false
    }
}

enum DebugLogger {
    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        print("[\(filename):\(line)] \(function): \(message)")
        #endif
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        print("❌ [\(filename):\(line)] \(function): \(message)")
    }
}
