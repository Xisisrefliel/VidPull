import SwiftUI
import AppKit
import Combine

// Shared download manager instance
let sharedDownloadManager = DownloadManager()

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for URL scheme events
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "VidPull")
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create the popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 500)
        popover?.behavior = .transient
        popover?.animates = true
        
        // Set content with the shared download manager
        let contentView = MenuBarView()
            .environmentObject(sharedDownloadManager)
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }
    
    @objc func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit VidPull", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil  // Remove menu so left-click works again
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func showPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        handleIncomingURL(url)
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Handle vidpull:// URL scheme
        // Format: vidpull://download?url=<encoded_url>
        guard url.scheme == "vidpull" else { return }
        
        if url.host == "download" {
            // Parse the URL query parameter
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let urlParam = queryItems.first(where: { $0.name == "url" }),
               let videoURLString = urlParam.value {
                DispatchQueue.main.async { [weak self] in
                    // Set the URL directly on the shared manager
                    sharedDownloadManager.setURLFromExtension(videoURLString)
                    
                    // Open the popover
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self?.showPopover()
                    }
                }
            }
        }
    }
}

@main
struct yt_dlp_WrapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
