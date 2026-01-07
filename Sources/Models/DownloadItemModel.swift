import Foundation

struct DownloadItemModel: Identifiable, Equatable, Codable {
    let id: UUID
    let url: String
    let outputFolder: URL
    let startDate: Date
    var progress: Double
    var status: DownloadStatus
    var downloadedFileURL: URL?
    var errorMessage: String?
    var fileName: String?

    init(
        id: UUID = UUID(),
        url: String,
        outputFolder: URL,
        startDate: Date = Date(),
        progress: Double = 0.0,
        status: DownloadStatus = .pending,
        downloadedFileURL: URL? = nil,
        errorMessage: String? = nil,
        fileName: String? = nil
    ) {
        self.id = id
        self.url = url
        self.outputFolder = outputFolder
        self.startDate = startDate
        self.progress = progress
        self.status = status
        self.downloadedFileURL = downloadedFileURL
        self.errorMessage = errorMessage
        self.fileName = fileName
    }

    static func == (lhs: DownloadItemModel, rhs: DownloadItemModel) -> Bool {
        lhs.id == rhs.id
    }
}

enum DownloadStatus: String, Codable {
    case pending = "Waiting..."
    case downloading = "Downloading..."
    case extracting = "Extracting..."
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .downloading, .extracting: return "arrow.down.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }
}
