import Foundation

enum YTDLPError: LocalizedError {
    case ytDLPNotFound
    case invalidURL
    case downloadFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ytDLPNotFound:
            return "yt-dlp is not installed. Please install it with: brew install yt-dlp"
        case .invalidURL:
            return "Invalid URL provided"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .cancelled:
            return "Download was cancelled"
        }
    }
}

struct DownloadResult {
    let outputFolder: URL
    let downloadedFile: URL?
    let videoTitle: String?
}

actor YTDLPService {
    static let shared = YTDLPService()

    private var ytDLPPath: URL?
    private var runningTasks: [UUID: Process] = [:]
    private var downloadedFiles: [UUID: URL] = [:]
    private var videoTitles: [UUID: String] = [:]

    private init() {
        ytDLPPath = nil
    }

    func initialize() async {
        ytDLPPath = findYTDLP()
    }

    func isAvailable() -> Bool {
        return ytDLPPath != nil
    }

    func findYTDLP() -> URL? {
        let paths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    func runDownload(
        id: UUID,
        url: String,
        config: YTDLPConfig,
        progressHandler: @escaping (Double, String) -> Void,
        statusHandler: @escaping (DownloadStatus) -> Void,
        fileNameHandler: @escaping (String) -> Void,
        completionHandler: @escaping (Result<DownloadResult, YTDLPError>) -> Void
    ) async throws {
        guard let ytDLPPath = ytDLPPath else {
            throw YTDLPError.ytDLPNotFound
        }

        guard URL(string: url) != nil else {
            throw YTDLPError.invalidURL
        }

        let process = Process()
        runningTasks[id] = process
        downloadedFiles[id] = nil
        videoTitles[id] = nil

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = ytDLPPath
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var arguments: [String] = [
            "--no-check-certificates",
            "--no-playlist",
            "--newline",  // Force progress on new lines for better parsing
            "--progress-template", "[download] %(progress._percent_str)s of %(progress._total_bytes_str)s at %(progress._speed_str)s ETA %(progress._eta_str)s"
        ]

        if config.isPlaylist {
            arguments.removeAll { $0 == "--no-playlist" }
        }

        if config.format != .best {
            arguments.append("--format")
            arguments.append(config.format.ytDLPFormat)
        }

        arguments.append("--output")
        arguments.append("\(config.outputFolder.path)/%(title)s.%(ext)s")

        arguments.append(url)

        process.arguments = arguments

        let outputHandle = stdoutPipe.fileHandleForReading
        let errorHandle = stderrPipe.fileHandleForReading

        // Use availableData instead of readDataToEndOfFile for non-blocking reads
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }
            Task {
                await self?.parseOutput(id: id, output: output, progressHandler: progressHandler, statusHandler: statusHandler, fileNameHandler: fileNameHandler)
            }
        }

        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }
            Task {
                await self?.parseOutput(id: id, output: output, progressHandler: progressHandler, statusHandler: statusHandler, fileNameHandler: fileNameHandler)
            }
        }

        try process.run()

        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        // Clean up handlers
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        let wasCancelled = runningTasks[id] == nil
        runningTasks.removeValue(forKey: id)

        let exitCode = process.terminationStatus
        let downloadedFile = downloadedFiles[id]
        let videoTitle = videoTitles[id]
        
        // Cleanup temp files
        cleanupTempFiles(in: config.outputFolder)

        if wasCancelled {
            completionHandler(.failure(.cancelled))
        } else if exitCode == 0 {
            statusHandler(.completed)
            progressHandler(1.0, "Completed")
            let result = DownloadResult(
                outputFolder: config.outputFolder,
                downloadedFile: downloadedFile,
                videoTitle: videoTitle
            )
            completionHandler(.success(result))
        } else {
            completionHandler(.failure(.downloadFailed("Exit code: \(exitCode)")))
        }
    }

    func cancelDownload(id: UUID) {
        if let process = runningTasks[id] {
            process.terminate()
            runningTasks.removeValue(forKey: id)
        }
    }
    
    private func cleanupTempFiles(in folder: URL) {
        let fileManager = FileManager.default
        let tempExtensions = [".part", ".ytdl", ".temp", ".tmp"]
        
        do {
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files {
                let fileName = file.lastPathComponent
                for ext in tempExtensions {
                    if fileName.hasSuffix(ext) {
                        try? fileManager.removeItem(at: file)
                        break
                    }
                }
                // Also clean up .part.* files (like .part-Frag0)
                if fileName.contains(".part") {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Failed to cleanup temp files: \(error)")
        }
    }

    private func parseOutput(id: UUID, output: String, progressHandler: (Double, String) -> Void, statusHandler: (DownloadStatus) -> Void, fileNameHandler: (String) -> Void) {
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Extract video title from various yt-dlp output formats
            if line.contains("[download] Destination:") {
                // Extract filename from destination line
                if let destinationPath = line.components(separatedBy: "Destination:").last?.trimmingCharacters(in: .whitespaces) {
                    let fileName = URL(fileURLWithPath: destinationPath).deletingPathExtension().lastPathComponent
                    videoTitles[id] = fileName
                    fileNameHandler(fileName)
                    downloadedFiles[id] = URL(fileURLWithPath: destinationPath)
                }
                statusHandler(.downloading)
                continue
            }
            
            // Also try to get title from info extraction
            if line.contains("[info]") && line.contains(":") {
                // Sometimes title appears in info lines
                continue
            }
            
            // Extract title from "[download] Downloading video" or similar
            if line.hasPrefix("[") && line.contains("Downloading") {
                continue
            }

            if line.contains("[download]") {
                if let progress = extractProgress(from: line), progress >= 0 {
                    progressHandler(progress, line)
                    if progress >= 1.0 {
                        statusHandler(.extracting) // Post-processing
                    } else {
                        statusHandler(.downloading)
                    }
                }
                
                // Check for "100%" completion line
                if line.contains("100%") || line.contains("100.0%") {
                    progressHandler(1.0, line)
                }
            } else if line.contains("[ExtractAudio]") || line.contains("[Merger]") || line.contains("[ffmpeg]") {
                statusHandler(.extracting)
            } else if line.contains("[Metadata]") {
                statusHandler(.extracting)
            } else if line.contains("ERROR") || line.contains("error:") {
                statusHandler(.failed)
            }
            
            // Try to extract filename from Merger or ffmpeg output
            if (line.contains("[Merger]") || line.contains("[ffmpeg]")) && line.contains("Merging formats into") {
                if let mergedPath = line.components(separatedBy: "\"").dropFirst().first {
                    let fileName = URL(fileURLWithPath: String(mergedPath)).deletingPathExtension().lastPathComponent
                    videoTitles[id] = fileName
                    fileNameHandler(fileName)
                    downloadedFiles[id] = URL(fileURLWithPath: String(mergedPath))
                }
            }
            
            // Handle "has already been downloaded" case
            if line.contains("has already been downloaded") {
                progressHandler(1.0, "Already downloaded")
                statusHandler(.completed)
            }
        }
    }

    private func extractProgress(from line: String) -> Double? {
        // Match patterns like "45.2%" or "100%"
        let pattern = #"(\d+\.?\d*)%"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            let percentageString = String(line[range])
            return Double(percentageString).map { $0 / 100.0 }
        }
        return nil
    }
}
