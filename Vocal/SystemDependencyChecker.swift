import Foundation
import OSLog

/// Manages system dependency checking and setup for the app
class SystemDependencyChecker {
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: "me.nuanc.Vocal", category: "SystemDependencyChecker")
    private static let cache = NSCache<NSString, DependencyStatus>()
    private static let cacheTimeout: TimeInterval = 300 // 5 minutes
    private static var lastCheckTime: Date?
    
    private static let resourcesDirectory = Bundle.main.resourceURL?.appendingPathComponent("Resources")
    private static let embeddedYtDlpPath = Bundle.main.resourceURL?.appendingPathComponent("Resources/yt-dlp")
    private static let embeddedFfmpegPath = Bundle.main.resourceURL?.appendingPathComponent("Resources/ffmpeg")
    
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
    
    // MARK: - Public Methods
    
    /// Checks for all required dependencies
    /// - Returns: Array of dependency statuses
    static func checkDependencies() async -> [DependencyStatus] {
        // Fast path: check cache first
        if let cachedResults = getCachedResults(), shouldUseCachedResults() {
            logger.debug("Using cached dependency check results")
            return cachedResults
        }
        
        logger.info("Checking system dependencies")
        
        // Run checks with timeout
        if let results = await withTimeout(seconds: 5) { () async throws -> [DependencyStatus] in
            async let ytDlpStatus = checkYtDlp()
            async let ffmpegStatus = checkFfmpeg()
            return await [ytDlpStatus, ffmpegStatus]
        } {
            logger.info("Dependency check completed: \(results.map { $0.isInstalled ? "✅" : "❌" }.joined(separator: ", "))")
            cacheDependencyResults(results)
            return results
        }
        
        logger.warning("Dependency check timed out or failed")
        return []
    }
    
    /// Attempts to setup missing dependencies
    /// - Returns: True if setup was successful
    static func setupMissingDependencies() async -> Bool {
        logger.info("Setting up missing dependencies")
        
        do {
            // Create resources directory if it doesn't exist
            if let resourcesDir = resourcesDirectory {
                if !FileManager.default.fileExists(atPath: resourcesDir.path) {
                    try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
                    logger.info("Created resources directory: \(resourcesDir.path)")
                }
            }
            
            // Setup yt-dlp
            try await setupYtDlp()
            
            // Setup ffmpeg
            try await setupFfmpeg()
            
            // Clear cache to force re-check
            cache.removeAllObjects()
            lastCheckTime = nil
            
            // Verify setup was successful
            let dependencies = await checkDependencies()
            let allInstalled = dependencies.allSatisfy { $0.isInstalled }
            
            logger.info("Dependency setup \(allInstalled ? "successful" : "failed")")
            return allInstalled
        } catch {
            logger.error("Failed to set up dependencies: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Setup yt-dlp from embedded resources or try to make existing binary executable
    private static func setupYtDlp() async throws {
        logger.info("Setting up yt-dlp")
        
        // Check if embedded binary exists and just needs to be made executable
        if let embeddedPath = embeddedYtDlpPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath) {
            try makeExecutable(path: embeddedPath)
            logger.info("Made existing yt-dlp executable: \(embeddedPath)")
            return
        }
        
        // Check if we have the zip file to extract
        if let ytDlpZipPath = Bundle.main.path(forResource: "yt-dlp", ofType: "zip"),
           let resourcesDir = resourcesDirectory?.path {
            try await extractAndSetupTool(from: ytDlpZipPath, to: resourcesDir, name: "yt-dlp")
            logger.info("Successfully extracted and set up yt-dlp")
            return
        }
        
        logger.error("No embedded yt-dlp resources found")
        throw DependencyError.embeddedResourceMissing
    }
    
    /// Setup ffmpeg from embedded resources or try to make existing binary executable
    private static func setupFfmpeg() async throws {
        logger.info("Setting up ffmpeg")
        
        // Check if embedded binary exists and just needs to be made executable
        if let embeddedPath = embeddedFfmpegPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath) {
            try makeExecutable(path: embeddedPath)
            logger.info("Made existing ffmpeg executable: \(embeddedPath)")
            return
        }
        
        // Check if we have the zip file to extract
        if let ffmpegZipPath = Bundle.main.path(forResource: "ffmpeg", ofType: "zip"),
           let resourcesDir = resourcesDirectory?.path {
            try await extractAndSetupTool(from: ffmpegZipPath, to: resourcesDir, name: "ffmpeg")
            logger.info("Successfully extracted and set up ffmpeg")
            return
        }
        
        logger.error("No embedded ffmpeg resources found")
        throw DependencyError.embeddedResourceMissing
    }
    
    /// Make a file executable
    private static func makeExecutable(path: String) throws {
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
                throw DependencyError.permissionDenied
            }
            
            logger.info("Successfully made file executable: \(path)")
        } catch {
            logger.error("Error making file executable: \(error.localizedDescription)")
            throw DependencyError.permissionDenied
        }
    }
    
    /// Extract a tool from a zip file and make it executable
    private static func extractAndSetupTool(from zipPath: String, to directory: String, name: String) async throws {
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
                throw DependencyError.extractionFailed
            }
            
            let extractedPath = "\(directory)/\(name)"
            
            // Verify the file was extracted
            guard FileManager.default.fileExists(atPath: extractedPath) else {
                logger.error("Extraction succeeded but file not found at \(extractedPath)")
                throw DependencyError.extractionFailed
            }
            
            try makeExecutable(path: extractedPath)
            logger.info("Successfully extracted and made executable: \(extractedPath)")
        } catch {
            logger.error("Error extracting \(name): \(error.localizedDescription)")
            throw DependencyError.extractionFailed
        }
    }
    
    /// Checks if yt-dlp is available
    private static func checkYtDlp() async -> DependencyStatus {
        logger.debug("Checking for yt-dlp")
        
        // First check if we have embedded yt-dlp
        if let embeddedPath = embeddedYtDlpPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath) {
            // Check if it's executable
            if isExecutable(path: embeddedPath) {
                logger.info("Found embedded executable yt-dlp at: \(embeddedPath)")
                return DependencyStatus(
                    dependency: .ytDlp,
                    isInstalled: true,
                    path: embeddedPath,
                    version: await getToolVersion(path: embeddedPath),
                    type: .embedded,
                    isEmbeddable: true
                )
            } else {
                logger.info("Found embedded non-executable yt-dlp at: \(embeddedPath)")
                return DependencyStatus(
                    dependency: .ytDlp,
                    isInstalled: false,
                    path: embeddedPath,
                    version: nil,
                    type: .embeddable(
                        .ytDlp,
                        "chmod +x \"\(embeddedPath)\"",
                        URL(string: "https://github.com/yt-dlp/yt-dlp#installation")!
                    ),
                    isEmbeddable: true
                )
            }
        }
        
        // Check system paths
        for path in ytDlpPaths {
            if FileManager.default.fileExists(atPath: path) && isExecutable(path: path) {
                logger.info("Found system yt-dlp at: \(path)")
                return DependencyStatus(
                    dependency: .ytDlp,
                    isInstalled: true,
                    path: path,
                    version: await getToolVersion(path: path),
                    type: .system,
                    isEmbeddable: true
                )
            }
        }
        
        // Check if we have the zip resource
        if Bundle.main.path(forResource: "yt-dlp", ofType: "zip") != nil {
            logger.info("Found yt-dlp.zip resource")
            return DependencyStatus(
                dependency: .ytDlp,
                isInstalled: false,
                path: nil,
                version: nil,
                type: .embeddable(
                    .ytDlp,
                    "Automatic setup available",
                    URL(string: "https://github.com/yt-dlp/yt-dlp#installation")!
                ),
                isEmbeddable: true
            )
        }
        
        // Not found anywhere
        logger.warning("yt-dlp not found")
        return DependencyStatus(
            dependency: .ytDlp,
            isInstalled: false,
            path: nil,
            version: nil,
            type: .missing(
                .ytDlp,
                "brew install yt-dlp",
                URL(string: "https://github.com/yt-dlp/yt-dlp#installation")!
            ),
            isEmbeddable: true
        )
    }
    
    /// Checks if ffmpeg is available
    private static func checkFfmpeg() async -> DependencyStatus {
        logger.debug("Checking for ffmpeg")
        
        // First check if we have embedded ffmpeg
        if let embeddedPath = embeddedFfmpegPath?.path,
           FileManager.default.fileExists(atPath: embeddedPath) {
            // Check if it's executable
            if isExecutable(path: embeddedPath) {
                logger.info("Found embedded executable ffmpeg at: \(embeddedPath)")
                return DependencyStatus(
                    dependency: .ffmpeg,
                    isInstalled: true,
                    path: embeddedPath,
                    version: await getToolVersion(path: embeddedPath),
                    type: .embedded,
                    isEmbeddable: true
                )
            } else {
                logger.info("Found embedded non-executable ffmpeg at: \(embeddedPath)")
                return DependencyStatus(
                    dependency: .ffmpeg,
                    isInstalled: false,
                    path: embeddedPath,
                    version: nil,
                    type: .embeddable(
                        .ffmpeg,
                        "chmod +x \"\(embeddedPath)\"",
                        URL(string: "https://ffmpeg.org/download.html")!
                    ),
                    isEmbeddable: true
                )
            }
        }
        
        // Check system paths
        for path in ffmpegPaths {
            if FileManager.default.fileExists(atPath: path) && isExecutable(path: path) {
                logger.info("Found system ffmpeg at: \(path)")
                return DependencyStatus(
                    dependency: .ffmpeg,
                    isInstalled: true,
                    path: path,
                    version: await getToolVersion(path: path),
                    type: .system,
                    isEmbeddable: true
                )
            }
        }
        
        // Check if we have the zip resource
        if Bundle.main.path(forResource: "ffmpeg", ofType: "zip") != nil {
            logger.info("Found ffmpeg.zip resource")
            return DependencyStatus(
                dependency: .ffmpeg,
                isInstalled: false,
                path: nil,
                version: nil,
                type: .embeddable(
                    .ffmpeg,
                    "Automatic setup available",
                    URL(string: "https://ffmpeg.org/download.html")!
                ),
                isEmbeddable: true
            )
        }
        
        // Not found anywhere
        logger.warning("ffmpeg not found")
        return DependencyStatus(
            dependency: .ffmpeg,
            isInstalled: false,
            path: nil,
            version: nil,
            type: .missing(
                .ffmpeg,
                "brew install ffmpeg",
                URL(string: "https://ffmpeg.org/download.html")!
            ),
            isEmbeddable: true
        )
    }
    
    /// Gets the version of a tool
    private static func getToolVersion(path: String) async -> String? {
        let versionFlags = [
            "yt-dlp": "--version",
            "ffmpeg": "-version"
        ]
        
        let toolName = URL(fileURLWithPath: path).lastPathComponent
        guard let flag = versionFlags[toolName] else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [flag]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            
            let outputData = try outputPipe.fileHandleForReading.readToEnd()
            let output = outputData.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            process.waitUntilExit()
            
            if process.terminationStatus == 0 && output?.isEmpty == false {
                if let version = output?.components(separatedBy: .newlines).first {
                    logger.debug("Got version for \(toolName): \(version)")
                    return version
                }
            }
        } catch {
            logger.error("Error getting version for \(toolName): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Checks if a file is executable
    private static func isExecutable(path: String) -> Bool {
        logger.debug("Checking if file is executable: \(path)")
        
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        
        // Check for executable permission using POSIX properties
        if let posixPermissions = attributes?[.posixPermissions] as? NSNumber {
            let isExecutable = (posixPermissions.intValue & 0o111) != 0
            logger.debug("File at \(path) executable status: \(isExecutable)")
            return isExecutable
        }
        
        // Fallback: use FileManager.isExecutableFile
        let result = fileManager.isExecutableFile(atPath: path)
        logger.debug("FileManager reports executable status for \(path): \(result)")
        return result
    }
    
    /// Gets cached dependency check results
    private static func getCachedResults() -> [DependencyStatus]? {
        // Return nil if no cached results
        guard let ytDlpStatus = cache.object(forKey: "yt-dlp" as NSString),
              let ffmpegStatus = cache.object(forKey: "ffmpeg" as NSString) else {
            return nil
        }
        
        return [ytDlpStatus, ffmpegStatus]
    }
    
    /// Determines if cached results should be used
    private static func shouldUseCachedResults() -> Bool {
        guard let lastCheck = lastCheckTime else { return false }
        return Date().timeIntervalSince(lastCheck) < cacheTimeout
    }
    
    /// Caches dependency check results
    private static func cacheDependencyResults(_ results: [DependencyStatus]) {
        for status in results {
            cache.setObject(status, forKey: status.dependency.rawValue as NSString)
        }
        lastCheckTime = Date()
    }
    
    /// Run an operation with timeout
    private static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                // Add the actual operation
                group.addTask {
                    return try await operation()
                }
                
                // Add a timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    logger.warning("Operation timed out after \(seconds) seconds")
                    throw DependencyError.timeout
                }
                
                // Return first completed task
                do {
                    let result = try await group.next()
                    group.cancelAll()
                    return result
                } catch {
                    logger.error("Error during dependency check: \(error.localizedDescription)")
                    group.cancelAll()
                    throw error
                }
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Models

/// Represents a system dependency
enum Dependency: String {
    case ytDlp = "yt-dlp"
    case ffmpeg = "ffmpeg"
    
    var displayName: String {
        switch self {
        case .ytDlp: return "YouTube Downloader (yt-dlp)"
        case .ffmpeg: return "Audio Processor (ffmpeg)"
        }
    }
    
    var description: String {
        switch self {
        case .ytDlp: return "Used to download videos from YouTube"
        case .ffmpeg: return "Used to process audio from videos"
        }
    }
}

/// Represents where a dependency comes from
enum DependencySourceType {
    case system
    case embedded
    case missing(Dependency, String, URL)
    case embeddable(Dependency, String, URL)
}

/// Represents the status of a dependency
class DependencyStatus: NSObject {
    let dependency: Dependency
    let isInstalled: Bool
    let path: String?
    let version: String?
    let type: DependencySourceType
    let isEmbeddable: Bool
    
    init(dependency: Dependency, isInstalled: Bool, path: String?, version: String?, type: DependencySourceType, isEmbeddable: Bool) {
        self.dependency = dependency
        self.isInstalled = isInstalled
        self.path = path
        self.version = version
        self.type = type
        self.isEmbeddable = isEmbeddable
    }
}

/// Errors that can occur during dependency operations
enum DependencyError: Error {
    case timeout
    case permissionDenied
    case extractionFailed
    case embeddedResourceMissing
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
