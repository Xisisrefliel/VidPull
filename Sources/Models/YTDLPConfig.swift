import Foundation

struct YTDLPConfig: Equatable, Codable {
    var format: FormatOption = .best
    var isPlaylist: Bool = false
    var outputFolder: URL

    enum FormatOption: String, CaseIterable, Identifiable, Codable {
        case best = "best"
        case bestVideo = "bestvideo"
        case bestAudio = "bestaudio"
        case worst = "worst"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .best: return "Best (Video + Audio)"
            case .bestVideo: return "Best Video Only"
            case .bestAudio: return "Best Audio Only"
            case .worst: return "Worst Quality"
            }
        }

        var ytDLPFormat: String {
            switch self {
            case .best: return "best"
            case .bestVideo: return "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio"
            case .bestAudio: return "bestaudio[ext=m4a]/bestaudio"
            case .worst: return "worst"
            }
        }
    }

    init(format: FormatOption = .best, isPlaylist: Bool = false, outputFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.format = format
        self.isPlaylist = isPlaylist
        self.outputFolder = outputFolder
    }
}
