import Foundation
import SwiftUI
import UserNotifications
import Combine

extension Notification.Name {
    static let vidpullURLReceived = Notification.Name("vidpullURLReceived")
    static let openSettings = Notification.Name("openSettings")
}

class DownloadManager: ObservableObject {
    @Published var urlInput: String = ""
    @Published var downloads: [DownloadItemModel] = []
    @Published var config: YTDLPConfig
    @Published var errorMessage: String?
    @Published var visibleItemsCount: Int = 10
    @Published var isYTDLPAvailable: Bool = true

    private var ytDLPService = YTDLPService.shared
    private var activeTaskIds: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    
    // Queue settings
    var maxConcurrentDownloads: Int {
        AppSettingsManager.shared.settings.maxConcurrentDownloads
    }
    
    // History limit to prevent unbounded growth
    var maxHistoryItems: Int {
        AppSettingsManager.shared.settings.maxHistoryItems
    }
    
    // MARK: - Computed Properties
    
    /// Currently downloading items
    var activeDownloads: [DownloadItemModel] {
        downloads.filter { $0.status == .downloading || $0.status == .extracting }
    }
    
    /// Items waiting in queue
    var queuedDownloads: [DownloadItemModel] {
        downloads.filter { $0.status == .queued }
    }
    
    /// Is any download in progress?
    var isDownloading: Bool {
        !activeDownloads.isEmpty
    }
    
    /// Total active + queued count for badge
    var pendingCount: Int {
        activeDownloads.count + queuedDownloads.count
    }
    
    // MARK: - Persistence
    
    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newAppFolder = appSupport.appendingPathComponent("VidPull", isDirectory: true)
        let oldAppFolder = appSupport.appendingPathComponent("yt-dlp-Wrapper", isDirectory: true)
        
        // Migrate from old folder name if it exists
        if fm.fileExists(atPath: oldAppFolder.path) && !fm.fileExists(atPath: newAppFolder.path) {
            try? fm.moveItem(at: oldAppFolder, to: newAppFolder)
        }
        
        try? fm.createDirectory(at: newAppFolder, withIntermediateDirectories: true)
        return newAppFolder
    }()
    
    private static var historyFileURL: URL {
        appSupportDirectory.appendingPathComponent("history.json")
    }
    
    private static var configFileURL: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    init() {
        // Load persisted config or use defaults
        self.config = Self.loadConfig() ?? YTDLPConfig(
            outputFolder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        )
        
        // Load persisted history
        self.downloads = Self.loadHistory()
        
        // Listen for URL scheme notifications
        NotificationCenter.default.publisher(for: .vidpullURLReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let url = notification.userInfo?["url"] as? String {
                    self?.setURLFromExtension(url)
                }
            }
            .store(in: &cancellables)
        
        Task {
            await ytDLPService.initialize()
            await checkYTDLPStatus()
        }
    }
    
    // MARK: - History Persistence
    
    private static func loadHistory() -> [DownloadItemModel] {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let items = try JSONDecoder().decode([DownloadItemModel].self, from: data)
            // Filter out any active/queued items from previous sessions (can't resume)
            return items.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
        } catch {
            print("Failed to load history: \(error)")
            return []
        }
    }
    
    private func saveHistory() {
        // Only persist terminal states, limited to maxHistoryItems
        var itemsToSave = downloads.filter { 
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled 
        }
        
        // Enforce history limit - keep most recent items
        if itemsToSave.count > maxHistoryItems {
            itemsToSave = Array(itemsToSave.prefix(maxHistoryItems))
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(itemsToSave)
            try data.write(to: Self.historyFileURL, options: .atomic)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    // MARK: - Config Persistence
    
    private static func loadConfig() -> YTDLPConfig? {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: configFileURL)
            return try JSONDecoder().decode(YTDLPConfig.self, from: data)
        } catch {
            print("Failed to load config: \(error)")
            return nil
        }
    }
    
    private func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: Self.configFileURL, options: .atomic)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
    
    // MARK: - Visible Items Management
    
    /// History items only (completed, failed, cancelled) - excludes active and queued
    var visibleDownloads: [DownloadItemModel] {
        let history = downloads.filter { 
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled 
        }
        return Array(history.prefix(visibleItemsCount))
    }
    
    var hasMoreItems: Bool {
        let historyItems = downloads.filter { $0.status.isTerminal }
        return historyItems.count > visibleItemsCount
    }
    
    var remainingItemsCount: Int {
        let historyItems = downloads.filter { $0.status.isTerminal }
        return max(0, historyItems.count - visibleItemsCount)
    }
    
    func loadMore() {
        visibleItemsCount += 10
    }
    
    func resetVisibleItems() {
        visibleItemsCount = 10
    }

    private func checkYTDLPStatus() async {
        let isAvailable = await ytDLPService.isAvailable()
        await MainActor.run {
            self.isYTDLPAvailable = isAvailable
            if !isAvailable {
                self.errorMessage = "yt-dlp not found. Install with: brew install yt-dlp"
            } else {
                self.errorMessage = nil
            }
        }
    }
    
    /// Refresh yt-dlp availability status
    func refreshYTDLPStatus() {
        Task {
            await checkYTDLPStatus()
        }
    }

    func setOutputFolder(_ url: URL) {
        config.outputFolder = url
        saveConfig()
    }
    
    /// Sets the URL input from an external source (e.g., Chrome extension via URL scheme)
    func setURLFromExtension(_ urlString: String) {
        urlInput = urlString
    }
    
    func setFormat(_ format: YTDLPConfig.FormatOption) {
        config.format = format
        saveConfig()
    }
    
    func setPlaylist(_ isPlaylist: Bool) {
        config.isPlaylist = isPlaylist
        saveConfig()
    }

    // MARK: - Download Queue Management
    
    /// Add a download to the queue and start processing
    func queueDownload() {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        
        // Clear input immediately to prevent double-submissions
        urlInput = ""
        
        let taskId = UUID()
        let downloadItem = DownloadItemModel(
            id: taskId,
            url: url,
            outputFolder: config.outputFolder,
            status: .queued,
            format: config.format
        )

        downloads.insert(downloadItem, at: 0)
        
        // Process the queue
        processQueue()
    }
    
    /// Start download (alias for queueDownload for backward compatibility)
    func startDownload() {
        queueDownload()
    }
    
    /// Process the download queue - start downloads up to maxConcurrentDownloads
    private func processQueue() {
        // Use activeTaskIds count to avoid race conditions
        let currentActiveCount = activeTaskIds.count
        let availableSlots = maxConcurrentDownloads - currentActiveCount
        
        guard availableSlots > 0 else { return }
        
        // Get queued items that aren't already being processed
        let queuedItems = downloads.filter { $0.status == .queued && !activeTaskIds.contains($0.id) }
        let itemsToStart = Array(queuedItems.prefix(availableSlots))
        
        for item in itemsToStart {
            // Mark as active immediately to prevent double-processing
            activeTaskIds.insert(item.id)
            startDownloadTask(item)
        }
    }
    
    /// Start a specific download task
    private func startDownloadTask(_ item: DownloadItemModel) {
        updateStatus(id: item.id, status: .downloading)
        
        Task {
            do {
                // Create config with the item's saved format
                var itemConfig = config
                itemConfig.format = item.format ?? config.format
                itemConfig.outputFolder = item.outputFolder
                
                try await ytDLPService.runDownload(
                    id: item.id,
                    url: item.url,
                    config: itemConfig
                ) { [weak self] progress, statusText in
                    Task { @MainActor in
                        self?.updateProgress(id: item.id, progress: progress, status: .downloading)
                    }
                } statusHandler: { [weak self] status in
                    Task { @MainActor in
                        self?.updateStatus(id: item.id, status: status)
                    }
                } fileNameHandler: { [weak self] fileName in
                    Task { @MainActor in
                        self?.updateFileName(id: item.id, fileName: fileName)
                    }
                } completionHandler: { [weak self] result in
                    Task { @MainActor in
                        self?.handleCompletion(id: item.id, result: result)
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(id: item.id, error: error)
                }
            }
        }
    }
    
    /// Cancel a specific download
    func cancelDownload(_ item: DownloadItemModel) async {
        await ytDLPService.cancelDownload(id: item.id)
        activeTaskIds.remove(item.id)
        updateStatus(id: item.id, status: .cancelled)
        saveHistory()
        
        // Process queue to start next download
        processQueue()
    }
    
    /// Cancel the first active download (for backward compatibility)
    func cancelDownload() async {
        guard let firstActive = activeDownloads.first else { return }
        await cancelDownload(firstActive)
    }
    
    /// Cancel all downloads (active and queued)
    func cancelAllDownloads() async {
        // Cancel all active downloads
        for item in activeDownloads {
            await ytDLPService.cancelDownload(id: item.id)
            activeTaskIds.remove(item.id)
            updateStatus(id: item.id, status: .cancelled)
        }
        
        // Cancel all queued downloads
        for item in queuedDownloads {
            updateStatus(id: item.id, status: .cancelled)
        }
        
        saveHistory()
    }
    
    /// Remove a queued download before it starts
    func removeFromQueue(_ item: DownloadItemModel) {
        guard item.status == .queued else { return }
        downloads.removeAll { $0.id == item.id }
    }

    func openFile(_ item: DownloadItemModel) {
        guard let fileURL = item.downloadedFileURL else {
            openFolder(item)
            return
        }

        NSWorkspace.shared.open(fileURL)
    }

    func openFolder(_ item: DownloadItemModel) {
        NSWorkspace.shared.open(item.outputFolder)
    }

    func clearCompleted() {
        downloads.removeAll { $0.status == .completed }
        saveHistory()
        resetVisibleItems()
    }
    
    func clearAll() {
        downloads.removeAll { 
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled 
        }
        saveHistory()
        resetVisibleItems()
    }
    
    func retryDownload(_ item: DownloadItemModel) {
        guard item.status == .failed || item.status == .cancelled else { return }
        
        // Remove the failed item from history
        downloads.removeAll { $0.id == item.id }
        
        // Queue a new download with the same URL
        let taskId = UUID()
        let downloadItem = DownloadItemModel(
            id: taskId,
            url: item.url,
            outputFolder: item.outputFolder,
            status: .queued,
            format: item.format
        )
        
        downloads.insert(downloadItem, at: 0)
        processQueue()
    }
    
    func removeDownload(_ item: DownloadItemModel) {
        downloads.removeAll { $0.id == item.id }
        saveHistory()
    }

    private func updateProgress(id: UUID, progress: Double, status: DownloadStatus) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].progress = progress
            downloads[index].status = status
        }
    }

    private func updateStatus(id: UUID, status: DownloadStatus) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = status
        }
    }

    private func updateFileName(id: UUID, fileName: String) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].fileName = fileName
        }
    }

    private func handleCompletion(id: UUID, result: Result<DownloadResult, YTDLPError>) {
        activeTaskIds.remove(id)
        
        switch result {
        case .success(let downloadResult):
            if let index = downloads.firstIndex(where: { $0.id == id }) {
                downloads[index].status = .completed
                downloads[index].progress = 1.0
                downloads[index].downloadedFileURL = downloadResult.downloadedFile ?? downloadResult.outputFolder
                if let title = downloadResult.videoTitle {
                    downloads[index].fileName = title
                }
            }
            
            if AppSettingsManager.shared.settings.showNotifications {
                let title = downloadResult.videoTitle ?? "Video"
                sendNotification(title: "Download Complete", body: "\(title) has finished downloading.")
            }
            saveHistory()
            
        case .failure(let error):
            handleError(id: id, error: error)
        }
        
        // Process queue to start next download
        processQueue()
    }

    private func handleError(id: UUID, error: Error) {
        activeTaskIds.remove(id)
        
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .failed
            downloads[index].errorMessage = error.localizedDescription
        }
        
        if AppSettingsManager.shared.settings.showNotifications {
            sendNotification(title: "Download Failed", body: error.localizedDescription)
        }
        saveHistory()
        
        // Process queue to start next download
        processQueue()
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
}
