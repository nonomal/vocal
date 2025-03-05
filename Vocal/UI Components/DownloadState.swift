import SwiftUI
enum DownloadState {
    case idle
    case preparing
    case downloading(progress: Double, speed: String?, eta: String?, size: String?)
    case processing
    case completed
    case error(String)
    
    var progressText: String {
        switch self {
        case .idle:
            return ""
        case .preparing:
            return "Preparing download..."
        case .downloading(_, let speed, let eta, let size):
            let parts = [speed, eta, size].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .processing:
            return "Processing..."
        case .completed:
            return "Download completed"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}