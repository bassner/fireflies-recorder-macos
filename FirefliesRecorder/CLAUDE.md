# Fireflies Recorder - macOS Menu Bar App

## Overview
A macOS menu bar application that records meetings by capturing system audio + microphone, saves as M4A, and uploads to Fireflies.ai for transcription.

## Requirements
- macOS 14.2+ (required for Core Audio Taps / ScreenCaptureKit system audio)
- Xcode 15+
- Swift 5.9+

## Project Structure
```
FirefliesRecorder/
├── FirefliesRecorderApp.swift      # App entry point with MenuBarExtra
├── Info.plist                       # Permissions, LSUIElement
├── FirefliesRecorder.entitlements   # App sandbox, audio entitlements
│
├── Views/
│   ├── MenuBarView.swift            # Main dropdown UI
│   ├── AudioLevelMeter.swift        # Horizontal audio level bar
│   ├── ToastView.swift              # Floating notification overlay
│   └── SettingsView.swift           # Settings window
│
├── Services/
│   ├── AudioRecorder.swift          # Orchestrates recording
│   ├── SystemAudioCapture.swift     # ScreenCaptureKit for system audio
│   ├── MicrophoneCapture.swift      # AVAudioEngine mic capture
│   ├── AudioMixer.swift             # Mixes both streams to M4A
│   └── AudioDeviceManager.swift     # List/select microphones
│
├── Services/Upload/
│   ├── FileHostingService.swift     # Upload to file.io
│   └── FirefliesAPI.swift           # GraphQL upload mutation
│
├── Managers/
│   ├── RecordingState.swift         # Observable recording state
│   ├── SettingsManager.swift        # UserDefaults + Keychain wrapper
│   ├── KeyboardShortcutManager.swift# Global hotkey setup
│   └── ToastManager.swift           # Floating toast notifications
│
└── Resources/
    └── Assets.xcassets              # App icons
```

## Dependencies (Swift Package Manager)
- `KeyboardShortcuts` (sindresorhus) - Global hotkey support

## Permissions Required
1. **Microphone** - For voice recording
2. **Screen Recording** - For system audio capture (ScreenCaptureKit)
3. **Input Monitoring** - For global keyboard shortcuts (optional)

## Key Technical Notes

### System Audio Capture (macOS 14.2+)
Uses ScreenCaptureKit instead of deprecated Core Audio Taps:
- Requires screen recording permission
- Captures all system audio excluding the app's own audio
- Uses `SCStream` with audio-only configuration

### Audio Mixing
- Both streams converted to 48kHz stereo
- Mixed and encoded to AAC in M4A container
- Uses AVAssetWriter for efficient encoding

### Fireflies Integration
1. Recording is first uploaded to file.io for temporary hosting
2. Public URL is then submitted to Fireflies GraphQL API
3. API key stored securely in macOS Keychain

## Build & Run

**ALWAYS use `./build.sh` to build the app.** Do NOT run xcodebuild directly.

```bash
./build.sh
```

This script:
1. Generates the Xcode project via xcodegen
2. Builds Release configuration
3. Signs the app with the identity from `.build.local` (or ad-hoc if not set)
4. Creates DMG at `build/FirefliesRecorder.dmg`

For development in Xcode:
```bash
xcodegen generate
open FirefliesRecorder.xcodeproj
# Build with Cmd+B, Run with Cmd+R
```

## Project Generation
This project uses **xcodegen** to generate the Xcode project from `project.yml`.
- New Swift files in `FirefliesRecorder/` are auto-discovered
- After adding files, run `xcodegen generate` to regenerate the project
- Don't manually edit `project.pbxproj` - changes will be overwritten

## Default Keyboard Shortcut
- **Cmd+Option+R** - Toggle recording on/off

## Known Limitations
- System audio capture requires screen recording permission (macOS requirement)
- App runs as menu bar only (no dock icon) via LSUIElement
- Recordings saved to ~/Documents/Fireflies Recordings/
