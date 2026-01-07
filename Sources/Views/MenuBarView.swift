import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var manager: DownloadManager

    var body: some View {
        VStack(spacing: 12) {
            headerSection

            Divider()

            inputSection

            optionsSection

            Divider()

            activeDownloadSection

            downloadHistorySection

            Spacer()
        }
        .padding(16)
        .frame(width: 400)
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            Text("yt-dlp")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if let error = manager.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("URL")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Paste URL here...", text: $manager.urlInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private var optionsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Format")
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Format", selection: $manager.config.format) {
                    ForEach(YTDLPConfig.FormatOption.allCases) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Toggle(isOn: $manager.config.isPlaylist) {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("Download Playlist")
                    Spacer()
                }
                .font(.caption)
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save to")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(manager.config.outputFolder.path)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button("Change") {
                        selectFolder()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Button(action: manager.startDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.urlInput.isEmpty || manager.isDownloading)

                if manager.isDownloading {
                    Button(action: {
                        Task {
                            await manager.cancelDownload()
                        }
                    }) {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var activeDownloadSection: some View {
        Group {
            if let active = manager.activeDownload {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Download")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    DownloadRowView(
                        item: active,
                        onOpen: { manager.openFile(active) },
                        onOpenFolder: { manager.openFolder(active) }
                    )
                }
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            }
        }
    }

    private var downloadHistorySection: some View {
        Group {
            if !manager.visibleDownloads.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("History")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Spacer()
                        
                        Menu {
                            Button("Clear Completed") {
                                manager.clearCompleted()
                            }
                            Button("Clear All", role: .destructive) {
                                manager.clearAll()
                            }
                        } label: {
                            Text("Clear")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .foregroundStyle(.blue)
                    }

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(manager.visibleDownloads) { item in
                                DownloadRowView(
                                    item: item,
                                    onOpen: { manager.openFile(item) },
                                    onOpenFolder: { manager.openFolder(item) },
                                    onRetry: item.status == .failed || item.status == .cancelled ? { manager.retryDownload(item) } : nil,
                                    onRemove: { manager.removeDownload(item) }
                                )
                            }
                            
                            if manager.hasMoreItems {
                                Button(action: { manager.loadMore() }) {
                                    HStack {
                                        Text("Load More (\(manager.remainingItemsCount) remaining)")
                                            .font(.caption)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 100, maxHeight: 250)
                }
                .padding(.top, 4)
            }
        }
    }

    private func selectFolder() {
        // Activate the app to ensure the panel appears in front
        NSApp.activate(ignoringOtherApps: true)
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder for downloads"
        panel.directoryURL = manager.config.outputFolder
        
        // Use runModal for menubar apps - begin() doesn't work without a window
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            manager.setOutputFolder(url)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(DownloadManager())
        .frame(width: 320)
}
