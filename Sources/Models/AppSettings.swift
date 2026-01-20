import Foundation

/// Application-wide settings persisted to disk
struct AppSettings: Codable, Equatable {
    /// Custom path to yt-dlp binary (nil = auto-detect)
    var customYTDLPPath: String?
    
    /// Enable system notifications
    var showNotifications: Bool = true
    
    /// Monitor clipboard for video URLs
    var clipboardMonitoring: Bool = false
    
    /// Auto-fill URL when video URL detected in clipboard
    var autoFillFromClipboard: Bool = true
    
    /// Maximum concurrent downloads (1-5)
    var maxConcurrentDownloads: Int = 2
    
    /// Maximum history items to keep
    var maxHistoryItems: Int = 100
    
    /// Default format for new downloads
    var defaultFormat: YTDLPConfig.FormatOption = .best
    
    /// Default output folder
    var defaultOutputFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    
    /// Show download count badge on menu bar icon
    var showMenuBarBadge: Bool = true
    
    // MARK: - Persistence
    
    private static var settingsFileURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("VidPull", isDirectory: true)
        try? fm.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("settings.json")
    }
    
    /// Load settings from disk
    static func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsFileURL.path) else {
            return AppSettings()
        }
        
        do {
            let data = try Data(contentsOf: settingsFileURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            print("Failed to load settings: \(error)")
            return AppSettings()
        }
    }
    
    /// Save settings to disk
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            try data.write(to: Self.settingsFileURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}

/// Observable wrapper for AppSettings to use in SwiftUI
class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()
    
    @Published var settings: AppSettings {
        didSet {
            settings.save()
        }
    }
    
    private init() {
        self.settings = AppSettings.load()
    }
    
    func reset() {
        settings = AppSettings()
    }
}
