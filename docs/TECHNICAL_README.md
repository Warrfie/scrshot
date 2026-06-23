# scrshot Technical README

This document is the developer-facing companion to the root [`README.md`](../README.md). It covers repository structure, architecture, capture and recording backends, build/test commands, and implementation constraints.

## Stack

- Language: `Swift`
- UI: `SwiftUI` app entry + `AppKit` windows, menus, and editor UI
- Screenshot capture: `CoreGraphics` + `ScreenCaptureKit`
- Recording: `ScreenCaptureKit`
- Hotkeys: Carbon global hotkey APIs
- Tests: `XCTest`

## Platform Support

- Base app and screenshot flow: `macOS 13+`
- Native video recording via `SCRecordingOutput`: `macOS 15+`
- Microphone recording modes: `macOS 15+`

## Repository Layout

- `Sources/scrshot/App.swift`
  App entry point, lifecycle setup, command menu, and `AppCoordinator`
- `Sources/scrshot/StatusItemController.swift`
  Menu bar item, about panel, recording toggle, and recording audio submenu
- `Sources/scrshot/AppPreferences.swift`
  Persistent settings, defaults, and user preference enums
- `Sources/scrshot/PreferencesWindowController.swift`
  Preferences window and controls for save/export/recording behavior
- `Sources/scrshot/HotkeyManager.swift`
  Carbon-based global capture hotkey registration and dispatch
- `Sources/scrshot/ScreenCaptureService.swift`
  Screenshot capture, permission flow, backend selection, and image cropping/compositing
- `Sources/scrshot/ScreenRecordingService.swift`
  Display recording session lifecycle, audio mode handling, and output file generation
- `Sources/scrshot/ScreenshotEditorWindowController.swift`
  Editor window lifecycle, toolbar, zoom, and completion flow
- `Sources/scrshot/ScreenshotEditorCanvasView.swift`
  Document model, annotation types, rendering, selection, editing, and undo/redo
- `Sources/scrshot/ImageSaver.swift`
  PNG file export
- `Sources/scrshot/ClipboardManager.swift`
  Pasteboard export
- `Sources/scrshot/LaunchAtLoginController.swift`
  Launch-at-login integration
- `Sources/scrshot/AppLogger.swift`
  Persistent application logs and diagnostics
- `Tests/scrshotTests/scrshotTests.swift`
  Unit coverage for crop/composite logic and editor document behavior

## Runtime Architecture

The application starts in `ScrshotApp`, which installs `AppDelegate` as the lifecycle owner. `AppDelegate` creates:

- shared preferences
- the launch-at-login controller
- the app coordinator
- the preferences window controller
- the menu bar status item controller

`AppCoordinator` owns the main workflow:

1. Registers the global capture hotkey
2. Applies preferences to runtime services
3. Captures the current display
4. Opens the editor window
5. Finalizes the edited image by exporting to clipboard, disk, or both
6. Starts and stops screen recording sessions

## Screenshot Pipeline

The screenshot path is centered in `ScreenCaptureService`.

Current flow:

1. Check screen recording permission with `CGPreflightScreenCaptureAccess()`
2. Resolve the target display from the current mouse location
3. Try the preferred ScreenCaptureKit capture path
4. Fall back to older/native alternatives if needed
5. Return a `CapturedScreen` model with display metadata and the `CGImage`
6. Open the native editor and export the rendered image on completion

The service also contains reusable image operations:

- crop a rectangular selection from one or more screens
- composite multiple captured displays into one image
- write debug images in debug builds
- emit diagnostics around visible windows and raw capture results

The root `README` only describes behavior. This file is the place to document backend order and fallback strategy.

## Recording Pipeline

Recording is handled by `ScreenRecordingService`.

Current behavior:

1. Validate permission with `CGPreflightScreenCaptureAccess()`
2. Resolve the current display from the mouse location
3. Build a timestamped output URL in the configured save directory
4. Load `SCShareableContent`
5. Create a `NativeRecordingSession`
6. Configure `SCStream` and `SCRecordingOutput`
7. Start capture and later finalize the recording file on stop

Audio modes are defined in `AppPreferences.RecordingAudioSource`:

- `System Audio`
- `No Audio`
- `Microphone Only`
- `System + Microphone`

File container options are defined in `AppPreferences.RecordingFileFormat`:

- `MOV`
- `MP4`

## Preferences Model

User settings are persisted in `UserDefaults` through `AppPreferences`.

The current preference surface includes:

- capture hotkey
- theme
- save directory
- launch at login
- export behavior
- file name prefix
- timestamp template
- reveal saved file in Finder
- recording audio source
- recording file format

Defaults currently include:

- hotkey: `Cmd + Shift + 1`
- save folder: not selected by default; first save asks the user to choose a user-accessible folder and stores a security-scoped bookmark
- user-selected save folders are persisted with security-scoped bookmarks
- export behavior: `Copy and Save`
- file prefix: `screenshot`
- timestamp template: `yyyy-MM-dd_HH-mm-ss`
- recording audio source: `No Audio`
- recording format: `MOV`

Privacy posture:

- capture permissions are requested from explicit user actions, not on launch
- denied Screen Recording or Microphone access is followed by an app-owned explanation before opening System Settings
- screenshots and recordings are local files; no network upload path exists in the current implementation
- App Store Connect privacy labels should disclose user-driven screen capture, optional microphone capture, optional system audio capture, and local file storage

## Editor Model

The editor implementation lives mainly in `ScreenshotEditorCanvasView.swift` and is split into two layers:

- `ScreenshotEditorDocument`
  Owns the source image, crop state, annotations, selection state, and undo/redo operations
- `ScreenshotEditorCanvasView`
  Handles rendering, hit testing, interaction, text editing, and tool-specific behavior

Supported annotation/tool concepts in code:

- crop
- arrow
- line
- rectangle highlight
- rectangle blur
- rectangle redact
- text

## Logging And Diagnostics

Persistent logs are written to:

```text
~/Library/Logs/scrshot/latest.log
```

Diagnostics are used for:

- application lifecycle events
- hotkey registration
- capture backend behavior
- recording failures
- permission-related issues
- runtime environment inspection

`ScreenCaptureService` also writes debug capture PNGs in debug builds under the user caches directory when that path is exercised.

## Build

### Xcode

1. Open `scrshot.xcodeproj`
2. Select the `scrshot` scheme
3. Pick a signing team if needed
4. Build and run

### Command Line

```bash
xcodebuild -project scrshot.xcodeproj -scheme scrshot -configuration Debug -derivedDataPath /tmp/scrshot-derived CODE_SIGNING_ALLOWED=NO build
```

### Build DMG Artifact

```bash
chmod +x scripts/build-dmg.sh
DEVELOPMENT_TEAM_VALUE=<APPLE_TEAM_ID> ./scripts/build-dmg.sh
```

By default this produces:

- `build/artifacts/scrshot-macos.dmg`
- `build/artifacts/scrshot-macos.sha256`

Installable DMG builds are signed by default so macOS TCC permissions use a stable app identity. For layout-only local packaging without a signing certificate, run `SIGNING_ALLOWED=NO ALLOW_UNSIGNED_DMG=YES ./scripts/build-dmg.sh`; do not use that unsigned app to validate Screen Recording or Microphone permissions.

The GitHub Actions workflow `.github/workflows/release-artifacts.yml` uses the same script and uploads the generated `.dmg` plus checksum as downloadable workflow artifacts.

### Build App Store Archive

```bash
DEVELOPMENT_TEAM_VALUE=<APPLE_TEAM_ID> ./scripts/build-appstore.sh
```

This creates an App Store Connect export under `build/appstore/`. Use this path for TestFlight or Mac App Store submission, not the Developer ID DMG path.

## Test

```bash
xcodebuild test -project scrshot.xcodeproj -scheme scrshot -derivedDataPath /tmp/scrshot-derived-test CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS'
```

The current automated coverage is mostly around:

- image crop logic
- multi-screen image composition
- editor document mutations
- annotation rendering behavior
- undo/redo flows

## Logging

Persistent logs are written to:

```text
~/Library/Logs/scrshot/latest.log
```

That log is useful when:

- permissions are weird
- the editor window fails to appear
- recording fails to start or finish
- macOS behaves like macOS

## Maintenance Notes

- The repository may be in a dirty worktree during active development. Avoid assuming the checked-out files are pristine.
- Recording features depend on newer macOS APIs than the screenshot/editor flow.
- User-facing docs should stay in the root `README`.
- Architecture, internals, commands, and file maps should stay in this technical document.
