import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settingsManager = AppSettingsManager.shared
    @State private var ytDLPStatus: YTDLPStatus = .checking
    @State private var ytDLPVersion: String = ""
    @State private var isUpdatingYTDLP: Bool = false
    @State private var updateMessage: String?
    
    enum YTDLPStatus {
        case checking
        case installed(path: String)
        case notFound
    }
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            downloadsTab
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            
            advancedTab
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear {
            checkYTDLPStatus()
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                Toggle("Show notifications", isOn: $settingsManager.settings.showNotifications)
                    .help("Show system notifications when downloads complete or fail")
                
                Toggle("Show badge on menu bar", isOn: $settingsManager.settings.showMenuBarBadge)
                    .help("Show download count badge on the menu bar icon")
            } header: {
                Text("Notifications")
            }
            
            Section {
                Toggle("Monitor clipboard for video URLs", isOn: $settingsManager.settings.clipboardMonitoring)
                    .help("Automatically detect video URLs copied to clipboard")
                
                if settingsManager.settings.clipboardMonitoring {
                    Toggle("Auto-fill URL field", isOn: $settingsManager.settings.autoFillFromClipboard)
                        .help("Automatically fill the URL field when a video URL is detected")
                        .padding(.leading, 20)
                }
            } header: {
                Text("Clipboard")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Downloads Tab
    
    private var downloadsTab: some View {
        Form {
            Section {
                Picker("Default quality", selection: $settingsManager.settings.defaultFormat) {
                    ForEach(YTDLPConfig.FormatOption.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                
                HStack {
                    Text("Default save location")
                    Spacer()
                    Text(settingsManager.settings.defaultOutputFolder.lastPathComponent)
                        .foregroundStyle(.secondary)
                    Button("Change...") {
                        selectOutputFolder()
                    }
                }
            } header: {
                Text("Defaults")
            }
            
            Section {
                Picker("Concurrent downloads", selection: $settingsManager.settings.maxConcurrentDownloads) {
                    ForEach(1...5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .help("Maximum number of downloads to run at the same time")
                
                Stepper("History limit: \(settingsManager.settings.maxHistoryItems) items",
                        value: $settingsManager.settings.maxHistoryItems,
                        in: 10...500,
                        step: 10)
                    .help("Maximum number of items to keep in download history")
            } header: {
                Text("Performance")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Advanced Tab
    
    private var advancedTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        switch ytDLPStatus {
                        case .checking:
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Checking yt-dlp...")
                            }
                        case .installed(let path):
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("yt-dlp installed")
                            }
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !ytDLPVersion.isEmpty {
                                Text("Version: \(ytDLPVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .notFound:
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("yt-dlp not found")
                            }
                            Text("Install with: brew install yt-dlp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if case .installed = ytDLPStatus {
                        Button(action: updateYTDLP) {
                            if isUpdatingYTDLP {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Update")
                            }
                        }
                        .disabled(isUpdatingYTDLP)
                    }
                }
                
                if let message = updateMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("Error") ? .red : .green)
                }
                
                HStack {
                    TextField("Custom yt-dlp path (optional)", text: Binding(
                        get: { settingsManager.settings.customYTDLPPath ?? "" },
                        set: { settingsManager.settings.customYTDLPPath = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Button("Browse...") {
                        selectYTDLPPath()
                    }
                }
            } header: {
                Text("yt-dlp")
            }
            
            Section {
                Button("Reset All Settings", role: .destructive) {
                    settingsManager.reset()
                }
                .help("Reset all settings to their default values")
            } header: {
                Text("Reset")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Actions
    
    private func checkYTDLPStatus() {
        ytDLPStatus = .checking
        
        Task {
            let paths = [
                settingsManager.settings.customYTDLPPath,
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp",
                "/usr/bin/yt-dlp"
            ].compactMap { $0 }
            
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    // Get version
                    let version = await getYTDLPVersion(at: path)
                    await MainActor.run {
                        ytDLPVersion = version ?? ""
                        ytDLPStatus = .installed(path: path)
                    }
                    return
                }
            }
            
            await MainActor.run {
                ytDLPStatus = .notFound
            }
        }
    }
    
    private func getYTDLPVersion(at path: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    private func updateYTDLP() {
        isUpdatingYTDLP = true
        updateMessage = nil
        
        Task {
            let process = Process()
            let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") 
                ? "/opt/homebrew/bin/brew" 
                : "/usr/local/bin/brew"
            
            guard FileManager.default.fileExists(atPath: brewPath) else {
                await MainActor.run {
                    updateMessage = "Error: Homebrew not found"
                    isUpdatingYTDLP = false
                }
                return
            }
            
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["upgrade", "yt-dlp"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let exitCode = process.terminationStatus
                await MainActor.run {
                    if exitCode == 0 {
                        updateMessage = "yt-dlp updated successfully!"
                        checkYTDLPStatus()
                    } else {
                        updateMessage = "Error: Update failed (exit code \(exitCode))"
                    }
                    isUpdatingYTDLP = false
                }
            } catch {
                await MainActor.run {
                    updateMessage = "Error: \(error.localizedDescription)"
                    isUpdatingYTDLP = false
                }
            }
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose default download folder"
        panel.directoryURL = settingsManager.settings.defaultOutputFolder
        
        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.settings.defaultOutputFolder = url
        }
    }
    
    private func selectYTDLPPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Select yt-dlp executable"
        panel.allowedContentTypes = [.unixExecutable]
        
        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.settings.customYTDLPPath = url.path
            checkYTDLPStatus()
        }
    }
}

#Preview {
    SettingsView()
}
