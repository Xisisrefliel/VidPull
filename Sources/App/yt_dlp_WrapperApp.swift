import SwiftUI

@main
struct yt_dlp_WrapperApp: App {
    @StateObject private var downloadManager = DownloadManager()

    var body: some Scene {
        MenuBarExtra("yt-dlp", systemImage: "arrow.down.circle.fill") {
            MenuBarView()
                .environmentObject(downloadManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
