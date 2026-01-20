# Screenshot Manager (macOS)

Local-first screenshot library for macOS: **menu bar quick actions + full timeline/grid app**.

## MVP (what this repo starts with)

- Menu bar item with:
  - Open Library
  - Copy Latest Screenshot
  - Reveal Latest in Finder
  - Quit
- Main window:
  - Watches a screenshot folder (default: `~/Desktop`)
  - Shows a grid of screenshots (newest first)
  - Preview selected screenshot
  - Actions: Copy Image, Copy File Path, Reveal in Finder

## Requirements

- macOS 13+ (Ventura)
- Xcode 15+ recommended (optional)
- Swift 5.9+

## Build and Run

### Option 1: Build as .app Bundle (Recommended)

From the repo root:

```bash
./build-app.sh
```

This will:
1. Build the release executable
2. Create a proper macOS `.app` bundle: `Screenshot Manager.app`
3. Set up Info.plist and bundle structure

Then double-click `Screenshot Manager.app` to run, or:
```bash
open "Screenshot Manager.app"
```

### Option 2: Run from Command Line

```bash
swift run
```

This launches a GUI app process (even though it's built as a SwiftPM executable).

**Note:** When running from command line, text input in dialogs may go to the terminal. Use the `.app` bundle for the best experience.

## Open in Xcode (optional)

- File → Open… → select this folder
- Run target `ScreenshotManagerApp`

## Notes

- Default watched folder is your Desktop. You can change it in-app (Settings coming next).
- If you have a custom macOS screenshot location, you can point the app to it (coming next).

