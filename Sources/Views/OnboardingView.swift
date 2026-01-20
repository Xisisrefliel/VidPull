import SwiftUI

/// First-run onboarding view to check dependencies and guide setup
struct OnboardingView: View {
    @State private var ytDLPInstalled = false
    @State private var ffmpegInstalled = false
    @State private var isChecking = true
    @State private var showingInstallInstructions = false
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Welcome to VidPull")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Download videos from YouTube and 1000+ sites")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Dependency checks
            VStack(alignment: .leading, spacing: 16) {
                Text("Checking Dependencies...")
                    .font(.headline)
                
                dependencyRow(
                    name: "yt-dlp",
                    description: "Video downloader engine",
                    isInstalled: ytDLPInstalled,
                    isChecking: isChecking
                )
                
                dependencyRow(
                    name: "ffmpeg",
                    description: "For merging video & audio streams",
                    isInstalled: ffmpegInstalled,
                    isChecking: isChecking
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            // Status and actions
            if !isChecking {
                if ytDLPInstalled && ffmpegInstalled {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All dependencies are installed!")
                                .foregroundStyle(.green)
                        }
                        .font(.headline)
                        
                        Button("Get Started") {
                            markOnboardingComplete()
                            DispatchQueue.main.async {
                                onComplete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Some dependencies are missing")
                                .foregroundStyle(.orange)
                        }
                        .font(.headline)
                        
                        if showingInstallInstructions {
                            installInstructions
                        } else {
                            HStack(spacing: 12) {
                                Button("Show Install Instructions") {
                                    showingInstallInstructions = true
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Check Again") {
                                    checkDependencies()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Button("Skip for Now") {
                            markOnboardingComplete()
                            DispatchQueue.main.async {
                                onComplete()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(30)
        .frame(width: 500, height: 550)
        .onAppear {
            checkDependencies()
        }
    }
    
    private func dependencyRow(name: String, description: String, isInstalled: Bool, isChecking: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isChecking {
                ProgressView()
                    .scaleEffect(0.7)
            } else if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            }
        }
    }
    
    private var installInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install using Homebrew:")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 8) {
                if !ytDLPInstalled {
                    installCommandRow("brew install yt-dlp")
                }
                if !ffmpegInstalled {
                    installCommandRow("brew install ffmpeg")
                }
            }
            
            Text("Don't have Homebrew? Visit brew.sh to install it first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Open Terminal") {
                    if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Check Again") {
                    checkDependencies()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func installCommandRow(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
            
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
    }
    
    private func checkDependencies() {
        isChecking = true
        
        Task {
            let ytDLP = await checkCommand("yt-dlp", args: ["--version"])
            let ffmpeg = await checkCommand("ffmpeg", args: ["-version"])
            
            await MainActor.run {
                ytDLPInstalled = ytDLP
                ffmpegInstalled = ffmpeg
                isChecking = false
            }
        }
    }
    
    private func checkCommand(_ command: String, args: [String]) async -> Bool {
        let paths = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }
    
    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
    
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
