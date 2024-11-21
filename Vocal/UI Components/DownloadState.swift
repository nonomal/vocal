import SwiftUI
enum DownloadState {
    case idle
    case preparing
    case downloading(progress: Double, speed: String?, eta: String?, size: String?)
    case processing
    
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
        }
    }
}