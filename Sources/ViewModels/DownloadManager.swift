import Foundation
import SwiftUI
import UserNotifications
import Combine

extension Notification.Name {
    static let vidpullURLReceived = Notification.Name("vidpullURLReceived")
}

class DownloadManager: ObservableObject {
    @Published var urlInput: String = ""
    @Published var downloads: [DownloadItemModel] = []
    @Published var activeDownload: DownloadItemModel?
    @Published var config: YTDLPConfig
    @Published var isDownloading: Bool = false
    @Published var errorMessage: String?
    @Published var visibleItemsCount: Int = 10

    private var ytDLPService = YTDLPService.shared
    private var currentTaskId: UUID?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Persistence
    
    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("yt-dlp-Wrapper", isDirectory: true)
        try? fm.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder
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
            // Filter out any pending/downloading items from previous sessions (can't resume)
            return items.filter { $0.status != .pending && $0.status != .downloading && $0.status != .extracting }
        } catch {
            print("Failed to load history: \(error)")
            return []
        }
    }
    
    private func saveHistory() {
        // Only persist terminal states
        let itemsToSave = downloads.filter { 
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled 
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
    
    var visibleDownloads: [DownloadItemModel] {
        let historyItems = downloads.filter { $0.status != .pending && $0.id != activeDownload?.id }
        return Array(historyItems.prefix(visibleItemsCount))
    }
    
    var hasMoreItems: Bool {
        let historyItems = downloads.filter { $0.status != .pending && $0.id != activeDownload?.id }
        return historyItems.count > visibleItemsCount
    }
    
    var remainingItemsCount: Int {
        let historyItems = downloads.filter { $0.status != .pending && $0.id != activeDownload?.id }
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
            if !isAvailable {
                self.errorMessage = "yt-dlp not found. Install with: brew install yt-dlp"
            }
        }
    }

    var ytDLPAvailable: Bool {
        Task {
            await MainActor.run {
                self.errorMessage = nil
            }
            let isAvailable = await ytDLPService.isAvailable()
            if !isAvailable {
                await MainActor.run {
                    self.errorMessage = "yt-dlp not found. Install with: brew install yt-dlp"
                }
            }
        }
        return true
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

    func startDownload() {
        guard !urlInput.isEmpty else { return }

        let taskId = UUID()
        currentTaskId = taskId
        let downloadItem = DownloadItemModel(
            id: taskId,
            url: urlInput,
            outputFolder: config.outputFolder,
            status: .pending
        )

        downloads.insert(downloadItem, at: 0)
        activeDownload = downloadItem
        isDownloading = true
        urlInput = ""  // Clear input after starting

        Task {
            do {
                try await ytDLPService.runDownload(
                    id: taskId,
                    url: downloadItem.url,
                    config: config
                ) { [weak self] progress, statusText in
                    Task { @MainActor in
                        self?.updateProgress(id: taskId, progress: progress, status: .downloading)
                    }
                } statusHandler: { [weak self] status in
                    Task { @MainActor in
                        self?.updateStatus(id: taskId, status: status)
                    }
                } fileNameHandler: { [weak self] fileName in
                    Task { @MainActor in
                        self?.updateFileName(id: taskId, fileName: fileName)
                    }
                } completionHandler: { [weak self] result in
                    Task { @MainActor in
                        self?.handleCompletion(id: taskId, result: result)
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(id: taskId, error: error)
                }
            }
        }
    }

    func cancelDownload() async {
        guard let taskId = currentTaskId else { return }

        await ytDLPService.cancelDownload(id: taskId)
        updateStatus(id: taskId, status: .cancelled)
        isDownloading = false
        activeDownload = nil
        currentTaskId = nil
        saveHistory()
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
        downloads.removeAll { $0.status != .pending && $0.status != .downloading && $0.status != .extracting }
        saveHistory()
        resetVisibleItems()
    }
    
    func retryDownload(_ item: DownloadItemModel) {
        guard item.status == .failed || item.status == .cancelled else { return }
        guard !isDownloading else { return }
        
        // Remove the failed item from history
        downloads.removeAll { $0.id == item.id }
        
        // Start a new download with the same URL
        urlInput = item.url
        startDownload()
    }
    
    func removeDownload(_ item: DownloadItemModel) {
        downloads.removeAll { $0.id == item.id }
        saveHistory()
    }

    private func updateProgress(id: UUID, progress: Double, status: DownloadStatus) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].progress = progress
            if activeDownload?.id == id {
                downloads[index].status = status
                activeDownload = downloads[index]
            }
        }
    }

    private func updateStatus(id: UUID, status: DownloadStatus) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = status
            if activeDownload?.id == id {
                activeDownload = downloads[index]
            }
        }
    }

    private func updateFileName(id: UUID, fileName: String) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].fileName = fileName
            if activeDownload?.id == id {
                activeDownload = downloads[index]
            }
        }
    }

    private func handleCompletion(id: UUID, result: Result<DownloadResult, YTDLPError>) {
        switch result {
        case .success(let downloadResult):
            if let index = downloads.firstIndex(where: { $0.id == id }) {
                downloads[index].status = .completed
                downloads[index].progress = 1.0
                downloads[index].downloadedFileURL = downloadResult.downloadedFile ?? downloadResult.outputFolder
                if let title = downloadResult.videoTitle {
                    downloads[index].fileName = title
                }
                activeDownload = nil
            }
            let title = downloadResult.videoTitle ?? "Video"
            sendNotification(title: "Download Complete", body: "\(title) has finished downloading.")
            saveHistory()
        case .failure(let error):
            handleError(id: id, error: error)
        }
        isDownloading = false
        currentTaskId = nil
    }

    private func handleError(id: UUID, error: Error) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .failed
            downloads[index].errorMessage = error.localizedDescription
            activeDownload = nil
        }
        sendNotification(title: "Download Failed", body: error.localizedDescription)
        isDownloading = false
        saveHistory()
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
