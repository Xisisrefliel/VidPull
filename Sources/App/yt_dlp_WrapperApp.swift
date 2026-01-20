import SwiftUI
import AppKit
import Combine

// Shared instances
let sharedDownloadManager = DownloadManager()
let sharedSettingsManager = AppSettingsManager.shared
let sharedClipboardMonitor = ClipboardMonitor.shared

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for URL scheme events
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // Listen for settings open notification
        NotificationCenter.default.publisher(for: .openSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.openSettings()
            }
            .store(in: &cancellables)
        
        // Setup clipboard monitoring
        setupClipboardMonitoring()
        
        setupMenuBar()
        
        // Show onboarding on first run
        if !OnboardingView.hasCompletedOnboarding {
            showOnboarding()
        }
    }
    
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to VidPull"
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        
        let onboardingView = OnboardingView { [weak self] in
            DispatchQueue.main.async {
                self?.onboardingWindow?.orderOut(nil)
                self?.onboardingWindow = nil
            }
        }
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupClipboardMonitoring() {
        // Start/stop monitoring based on settings
        sharedSettingsManager.$settings
            .receive(on: DispatchQueue.main)
            .sink { settings in
                if settings.clipboardMonitoring {
                    sharedClipboardMonitor.startMonitoring()
                } else {
                    sharedClipboardMonitor.stopMonitoring()
                }
            }
            .store(in: &cancellables)
        
        // Note: We don't auto-fill on detection anymore.
        // Instead, we check for detected URLs when the popover opens.
    }
    
    /// Check clipboard for video URL and auto-fill if enabled
    private func autoFillFromClipboardIfNeeded() {
        guard sharedSettingsManager.settings.clipboardMonitoring,
              sharedSettingsManager.settings.autoFillFromClipboard,
              sharedDownloadManager.urlInput.isEmpty else { return }
        
        // Check if there's a video URL in clipboard
        if let clipboardContent = NSPasteboard.general.string(forType: .string),
           sharedClipboardMonitor.isVideoURL(clipboardContent) {
            sharedDownloadManager.setURLFromExtension(clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VidPull", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil  // Remove menu so left-click works again
    }
    
    @objc func openSettings() {
        // Close popover if open
        popover?.performClose(nil)
        
        // Reuse existing window or create new one
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "VidPull Settings"
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow?.center()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Auto-fill from clipboard when opening (if enabled and URL field is empty)
            autoFillFromClipboardIfNeeded()
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func showPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if !popover.isShown {
            // Auto-fill from clipboard when opening (if enabled and URL field is empty)
            autoFillFromClipboardIfNeeded()
            
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
struct VidPullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
