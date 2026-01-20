# Fireflies Recorder for macOS

A lightweight macOS menu bar app that records meetings by capturing system audio and microphone, then uploads to [Fireflies.ai](https://fireflies.ai) for automatic transcription.

## Features

- **System Audio Capture** - Records all audio playing on your Mac (requires macOS 14.2+)
- **Microphone Recording** - Captures your voice during meetings
- **Auto-Upload** - Automatically uploads recordings to Fireflies.ai for transcription
- **Global Keyboard Shortcuts** - Start/stop recording from anywhere
- **Menu Bar App** - Stays out of your way, always accessible

## Requirements

- macOS 14.2 or later (required for Core Audio Taps)
- [Fireflies.ai](https://fireflies.ai) account and API key

## Installation

1. Download the latest DMG from [Releases](../../releases)
2. Open the DMG and drag **Fireflies Recorder** to your Applications folder
3. **Important**: Remove the quarantine attribute (required for unsigned apps):
   ```bash
   xattr -cr /Applications/FirefliesRecorder.app
   ```
4. Launch the app from Applications

## Setup

### Grant Permissions

On first launch, you'll need to grant the following permissions:

1. **Microphone Access** - Required to record your voice
2. **Screen Recording** - Required to capture system audio (this is how macOS grants access to system audio via Core Audio Taps)
3. **Keychain Access** - The app will store your Fireflies API key securely in the macOS Keychain

### Configure API Key

1. Click the waveform icon in your menu bar
2. Open **Settings** (gear icon)
3. Go to the **API** tab
4. Enter your Fireflies API key ([get it here](https://app.fireflies.ai/integrations/custom/fireflies))
5. Click **Save API Key**

## Usage

1. Click the waveform icon in the menu bar
2. Click **Start Recording** (or use your configured keyboard shortcut)
3. The icon changes to indicate recording is active
4. Click **Stop Recording** when done
5. If auto-upload is enabled and the recording meets the minimum duration, it will automatically upload to Fireflies.ai

## Settings

- **Audio Sources** - Choose to record microphone, system audio, or both
- **Auto-upload** - Automatically upload recordings to Fireflies
- **Minimum Duration** - Only upload recordings longer than this duration
- **Delete recordings on launch** - Clean up old recordings when the app starts
- **Launch at login** - Start the app automatically when you log in
- **Keyboard Shortcuts** - Configure global hotkeys for recording controls

## Building from Source

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation.

```bash
# Install XcodeGen
brew install xcodegen

# Build and create DMG
./build.sh
```

The script generates the Xcode project, builds, signs, and creates `build/FirefliesRecorder.dmg`.

To keep macOS permissions consistent across builds, create `.build.local` with your signing identity:
```bash
echo 'SIGNING_IDENTITY="Apple Development: you@example.com (TEAMID)"' > .build.local
```

For development in Xcode:
```bash
xcodegen generate
open FirefliesRecorder.xcodeproj
```

## License

MIT License - see [LICENSE](LICENSE) for details.
