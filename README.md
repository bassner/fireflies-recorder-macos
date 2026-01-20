<p align="center">
  <img src="https://github.com/user-attachments/assets/13a4460a-cb24-43ee-9fe7-27f5dd66965d" width="280" alt="Fireflies Recorder">
</p>

<h1 align="center">Fireflies Recorder for macOS</h1>

<p align="center">
  <strong>Record meetings with system audio + mic, auto-upload to Fireflies.ai for transcription</strong>
</p>

<p align="center">
  <a href="https://github.com/bassner/fireflies-recorder-macos/releases/latest"><img src="https://img.shields.io/github/v/release/bassner/fireflies-recorder-macos?style=flat-square" alt="Release"></a>
  <a href="https://github.com/bassner/fireflies-recorder-macos/blob/master/LICENSE"><img src="https://img.shields.io/github/license/bassner/fireflies-recorder-macos?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14.2+-blue?style=flat-square" alt="macOS 14.2+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" alt="Swift 5.9">
</p>

---

## Why?

Meeting bots are annoying. They join your calls, interrupt the flow, and make participants uncomfortable. **Fireflies Recorder** captures everything locally on your Mac—system audio from any app (Zoom, Meet, Teams, etc.) plus your microphone—then uploads to Fireflies.ai for transcription. No bots required.

## Features

- **System Audio Capture** — Records all audio playing on your Mac using ScreenCaptureKit
- **Microphone Recording** — Captures your voice with selectable input device
- **Auto-Upload** — Automatically uploads to Fireflies.ai when recording ends
- **Global Hotkeys** — Start/stop recording from anywhere (default: `⌘⌥R`)
- **Menu Bar App** — Lives in your menu bar, always one click away
- **Privacy First** — Everything stays on your Mac until you upload

## Quick Start

```bash
# 1. Download latest release
curl -sL https://github.com/bassner/fireflies-recorder-macos/releases/latest/download/FirefliesRecorder.dmg -o ~/Downloads/FirefliesRecorder.dmg

# 2. Mount, copy to Applications, and remove quarantine
hdiutil attach ~/Downloads/FirefliesRecorder.dmg
cp -R "/Volumes/Fireflies Recorder/FirefliesRecorder.app" /Applications/
hdiutil detach "/Volumes/Fireflies Recorder"
xattr -cr /Applications/FirefliesRecorder.app

# 3. Launch
open /Applications/FirefliesRecorder.app
```

Or manually: [Download DMG](https://github.com/bassner/fireflies-recorder-macos/releases/latest) → Drag to Applications → Run `xattr -cr /Applications/FirefliesRecorder.app`

## Setup

### 1. Grant Permissions

On first launch, grant these permissions when prompted:

| Permission | Why |
|------------|-----|
| **Microphone** | Record your voice |
| **Screen Recording** | Capture system audio (macOS requirement for ScreenCaptureKit) |

### 2. Add Your API Key

1. Get your API key from [Fireflies.ai](https://app.fireflies.ai/integrations/custom/fireflies)
2. Click the menu bar icon → **Settings** → **API** tab
3. Paste your key and click **Save**

## Usage

| Action | How |
|--------|-----|
| Start recording | Click menu bar icon → **Start Recording**, or press `⌘⌥R` |
| Stop recording | Click menu bar icon → **Stop Recording**, or press `⌘⌥R` |
| Mute mic | Press `⌘⌥M` |
| Open settings | Click menu bar icon → gear icon |

Recordings are saved to `~/Documents/Fireflies Recordings/` and auto-uploaded if enabled.

## Settings

| Setting | Description |
|---------|-------------|
| Audio Sources | Record mic, system audio, or both |
| Auto-upload | Upload to Fireflies.ai when recording ends |
| Minimum Duration | Only upload recordings longer than X minutes |
| Launch at Login | Start automatically when you log in |
| Keyboard Shortcuts | Customize global hotkeys |

## Requirements

- macOS 14.2 or later (ScreenCaptureKit requirement)
- [Fireflies.ai](https://fireflies.ai) account

## Building from Source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
./build.sh
```

Output: `build/FirefliesRecorder.dmg`

<details>
<summary>Development setup</summary>

```bash
xcodegen generate
open FirefliesRecorder.xcodeproj
# Build: ⌘B | Run: ⌘R
```

For consistent code signing (preserves macOS permissions across rebuilds):
```bash
echo 'SIGNING_IDENTITY="Apple Development: you@example.com (TEAMID)"' > .build.local
```

</details>

## License

GPL v3 — see [LICENSE](LICENSE)

---

<p align="center">
  <sub>Built with Swift and ScreenCaptureKit</sub>
</p>
