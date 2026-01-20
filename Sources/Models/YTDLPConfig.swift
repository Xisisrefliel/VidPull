import Foundation

struct YTDLPConfig: Equatable, Codable {
    var format: FormatOption = .best
    var isPlaylist: Bool = false
    var outputFolder: URL

    enum FormatOption: String, CaseIterable, Identifiable, Codable {
        case best = "best"
        case quality4K = "4k"
        case quality1080p = "1080p"
        case quality720p = "720p"
        case quality480p = "480p"
        case audioOnly = "audio"
        case worst = "worst"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .best: return "Best Quality"
            case .quality4K: return "4K (2160p)"
            case .quality1080p: return "1080p (Full HD)"
            case .quality720p: return "720p (HD)"
            case .quality480p: return "480p (SD)"
            case .audioOnly: return "Audio Only (MP3)"
            case .worst: return "Lowest Quality"
            }
        }
        
        var shortName: String {
            switch self {
            case .best: return "Best"
            case .quality4K: return "4K"
            case .quality1080p: return "1080p"
            case .quality720p: return "720p"
            case .quality480p: return "480p"
            case .audioOnly: return "Audio"
            case .worst: return "Low"
            }
        }

        /// Returns nil for default (best), otherwise the format string
        var ytDLPFormat: String? {
            switch self {
            case .best:
                // Default yt-dlp behavior - no format flag needed
                return nil
            case .quality4K:
                return "bv*[height<=2160]+ba/b"
            case .quality1080p:
                return "bv*[height<=1080]+ba/b"
            case .quality720p:
                return "bv*[height<=720]+ba/b"
            case .quality480p:
                return "bv*[height<=480]+ba/b"
            case .audioOnly:
                // Handled by additionalArguments
                return nil
            case .worst:
                return "wv*+wa/w"
            }
        }
        
        /// Additional yt-dlp arguments for this format
        var additionalArguments: [String] {
            switch self {
            case .audioOnly:
                // Extract audio and convert to MP3
                return ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
            default:
                return []
            }
        }
    }

    init(format: FormatOption = .best, isPlaylist: Bool = false, outputFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.format = format
        self.isPlaylist = isPlaylist
        self.outputFolder = outputFolder
    }
}
