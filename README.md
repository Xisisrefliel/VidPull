# VidPull

A macOS menu bar app that wraps [yt-dlp](https://github.com/yt-dlp/yt-dlp) for downloading videos and audio from YouTube and hundreds of other sites.

![Menu Bar App](https://img.shields.io/badge/macOS-Menu%20Bar%20App-blue)

## Features

- Download videos and playlists from YouTube and supported sites
- Real-time download progress with percentage and ETA
- Select video quality (Best, 1080p, 720p, 480p, Audio only)
- Choose custom download folder
- Download history with retry capability
- Clean temp files after download
- Runs quietly in your menu bar

## Prerequisites

Before installing VidPull, make sure you have the following installed on your macOS system:

### Required

```bash
# Install yt-dlp (video downloader)
brew install yt-dlp

# Install ffmpeg (required for format merging and audio extraction)
brew install ffmpeg
```

### For Building from Source

```bash
# Install XcodeGen (to generate the Xcode project)
brew install xcodegen
```

## Installation

### Option 1: Build from Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/VidPull.git
cd VidPull

# Run the setup script
chmod +x setup.sh
./setup.sh

# Open the app
open build/Debug/VidPull.app
```

### Option 2: Manual Build

```bash
# Generate Xcode project
xcodegen generate

# Build the project
xcodebuild -project yt-dlp-Wrapper.xcodeproj \
    -scheme yt-dlp-Wrapper \
    -configuration Debug \
    build

# Open the app
open build/Debug/VidPull.app
```

## Usage

1. Launch VidPull from your Applications folder or the build directory
2. The app will appear in your menu bar with a download icon
3. Paste a video or playlist URL
4. Optionally configure:
   - **Format**: Choose video quality or audio-only
   - **Playlist**: Toggle playlist downloading
   - **Save to**: Select download destination folder
5. Click **Download** to start
6. Track progress in the menu bar dropdown
7. Click **Open** or **Open Folder** when complete

## Troubleshooting

- **"yt-dlp is not installed"**: Make sure yt-dlp is in your PATH (`brew install yt-dlp`)
- **Download fails**: Ensure ffmpeg is installed (`brew install ffmpeg`)
- **App won't start**: Check Xcode build logs for errors

## License

MIT License - feel free to use and modify.

## Acknowledgments

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - The amazing video downloader
- [ffmpeg](https://ffmpeg.org/) - Multimedia framework
