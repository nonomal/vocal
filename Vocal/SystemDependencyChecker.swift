import Foundation

class SystemDependencyChecker {
    static func checkDependencies() async -> [DependencyStatus] {
        var statuses: [DependencyStatus] = []
        
        // Check Python
        let pythonStatus = await checkPython()
        statuses.append(pythonStatus)
        
        // Check yt-dlp
        let ytDlpStatus = await checkYtDlp()
        statuses.append(ytDlpStatus)
        
        return statuses
    }
    
    private static func checkPython() async -> DependencyStatus {
        let paths = ["/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return .installed(dependency: .python)
            }
        }
        
        return .missing(
            dependency: .python,
            installCommand: "brew install python3",
            helpURL: "https://www.python.org/downloads/"
        )
    }
    
    private static func checkYtDlp() async -> DependencyStatus {
        let paths = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return .installed(dependency: .ytDlp)
            }
        }
        
        return .missing(
            dependency: .ytDlp,
            installCommand: "brew install yt-dlp",
            helpURL: "https://github.com/yt-dlp/yt-dlp#installation"
        )
    }
}

enum SystemDependency: String {
    case python = "Python 3"
    case ytDlp = "yt-dlp"
}

enum DependencyStatus {
    case installed(dependency: SystemDependency)
    case missing(dependency: SystemDependency, installCommand: String, helpURL: String)
    
    var dependency: SystemDependency {
        switch self {
        case .installed(let dep), .missing(let dep, _, _):
            return dep
        }
    }
}
