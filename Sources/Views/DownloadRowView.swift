import SwiftUI

struct DownloadRowView: View {
    let item: DownloadItemModel
    let onOpen: () -> Void
    let onOpenFolder: () -> Void
    var onRetry: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    private var displayTitle: String {
        if let fileName = item.fileName, !fileName.isEmpty {
            return fileName
        }
        // Extract video ID or last path component from URL for cleaner display
        if let url = URL(string: item.url) {
            if let host = url.host, host.contains("youtube") || host.contains("youtu.be") {
                // Try to extract video ID from query string
                if let query = url.query {
                    let params = query.split(separator: "&")
                    for param in params {
                        let parts = param.split(separator: "=", maxSplits: 1)
                        if parts.count == 2 && parts[0] == "v" {
                            return "YouTube: \(parts[1])"
                        }
                    }
                }
                return url.lastPathComponent.isEmpty ? item.url : "YouTube: \(url.lastPathComponent)"
            }
            return url.host ?? item.url
        }
        return item.url
    }

    private var progressText: String {
        let percentage = Int(item.progress * 100)
        return "\(percentage)%"
    }

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: item.status.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 20, height: 20)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    // Status text
                    Text(item.status.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Progress indicator for active downloads
                    if item.status == .downloading || item.status == .extracting {
                        Text(progressText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .monospacedDigit()
                    }

                    // Error message for failed downloads
                    if item.status == .failed, let error = item.errorMessage {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                // Progress bar for active downloads
                if item.status == .downloading || item.status == .extracting {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(statusColor)
                }
            }

            Spacer()

            // Action buttons for completed downloads
            if item.status == .completed {
                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Open File")

                    Button(action: onOpenFolder) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    
                    if let onRemove = onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from History")
                    }
                }
            }
            
            // Action buttons for failed/cancelled downloads
            if item.status == .failed || item.status == .cancelled {
                HStack(spacing: 8) {
                    if let onRetry = onRetry {
                        Button(action: onRetry) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Retry Download")
                    }
                    
                    if let onRemove = onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from History")
                    }
                }
            }
            
            // Action buttons for queued downloads
            if item.status == .queued {
                HStack(spacing: 8) {
                    if let onCancel = onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from Queue")
                    }
                }
            }
            
            // Action buttons for active downloads
            if item.status == .downloading || item.status == .extracting {
                HStack(spacing: 8) {
                    if let onCancel = onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel Download")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(backgroundForStatus)
        .cornerRadius(6)
    }

    private var statusColor: Color {
        switch item.status {
        case .pending: return .gray
        case .queued: return .purple
        case .downloading, .extracting: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var backgroundForStatus: Color {
        switch item.status {
        case .downloading, .extracting:
            return Color.blue.opacity(0.08)
        case .queued:
            return Color.purple.opacity(0.06)
        case .completed:
            return Color.green.opacity(0.06)
        case .failed:
            return Color.red.opacity(0.08)
        case .cancelled:
            return Color.orange.opacity(0.08)
        case .pending:
            return Color.clear
        }
    }
}

#Preview {
    DownloadRowView(
        item: DownloadItemModel(
            url: "https://youtube.com/watch?v=example",
            outputFolder: URL(fileURLWithPath: "/Users/omer/Downloads"),
            progress: 0.45,
            status: .downloading
        ),
        onOpen: {},
        onOpenFolder: {}
    )
    .frame(width: 300)
    .padding()
}
