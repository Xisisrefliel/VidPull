import Foundation
import AppKit
import Combine

/// Monitors the clipboard for video URLs and notifies when one is detected
class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    @Published var detectedURL: String?
    @Published var isMonitoring: Bool = false
    
    private var timer: Timer?
    private var lastClipboardContent: String = ""
    private var lastChangeCount: Int = 0
    
    // Supported video URL patterns
    private let videoURLPatterns: [String] = [
        // YouTube
        "youtube.com/watch",
        "youtu.be/",
        "youtube.com/shorts/",
        "youtube.com/playlist",
        "youtube.com/live/",
        // Vimeo
        "vimeo.com/",
        // Twitter/X
        "twitter.com/.*/status/",
        "x.com/.*/status/",
        // TikTok
        "tiktok.com/",
        // Instagram
        "instagram.com/p/",
        "instagram.com/reel/",
        // Facebook
        "facebook.com/watch",
        "fb.watch/",
        // Reddit
        "reddit.com/.*/(comments|v)/",
        "v.redd.it/",
        // Twitch
        "twitch.tv/videos/",
        "clips.twitch.tv/",
        // Dailymotion
        "dailymotion.com/video/",
        // Bilibili
        "bilibili.com/video/",
        // SoundCloud
        "soundcloud.com/",
        // Bandcamp
        "bandcamp.com/track/",
        "bandcamp.com/album/",
    ]
    
    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount
        
        // Check clipboard every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        detectedURL = nil
    }
    
    func clearDetectedURL() {
        detectedURL = nil
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Only check if clipboard has changed
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard let content = pasteboard.string(forType: .string) else { return }
        
        // Don't re-detect the same content
        guard content != lastClipboardContent else { return }
        lastClipboardContent = content
        
        // Check if it looks like a video URL
        if isVideoURL(content) {
            DispatchQueue.main.async {
                self.detectedURL = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    
    /// Check if a string looks like a video URL
    func isVideoURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Must start with http:// or https://
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            return false
        }
        
        // Must be a valid URL
        guard URL(string: trimmed) != nil else {
            return false
        }
        
        // Check against known video URL patterns
        let lowercased = trimmed.lowercased()
        for pattern in videoURLPatterns {
            if lowercased.contains(pattern) {
                return true
            }
            
            // Try as regex for more complex patterns
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, range: range) != nil {
                    return true
                }
            }
        }
        
        return false
    }
}

// MARK: - Notification for clipboard URL detection
extension Notification.Name {
    static let clipboardURLDetected = Notification.Name("clipboardURLDetected")
}
