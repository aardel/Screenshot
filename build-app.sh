#!/bin/bash

# Build script to create a proper macOS .app bundle

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="Screenshot Manager"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="${SCRIPT_DIR}/.build"
RELEASE_DIR="${BUILD_DIR}/release"
APP_DIR="${SCRIPT_DIR}/${APP_BUNDLE}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building Screenshot Manager..."

# Build the release executable
swift build -c release

# Find the built executable (exclude dSYM files)
# Try the most common location first
EXECUTABLE="${BUILD_DIR}/arm64-apple-macosx/release/ScreenshotManagerApp"

# If not found, search for it
if [ ! -f "$EXECUTABLE" ]; then
    EXECUTABLE=$(find "${BUILD_DIR}" -type f -name "ScreenshotManagerApp" -executable | grep -v "dSYM" | grep -v "product" | grep "release" | head -1)
fi

# Last resort: any release executable
if [ -z "$EXECUTABLE" ] || [ ! -f "$EXECUTABLE" ]; then
    EXECUTABLE=$(find "${BUILD_DIR}" -type f -name "ScreenshotManagerApp" -executable | grep "release" | head -1)
fi

if [ -z "$EXECUTABLE" ]; then
    echo "Error: Could not find built executable"
    exit 1
fi

echo "Found executable: $EXECUTABLE"

# Remove old app bundle if it exists
if [ -d "${APP_DIR}" ]; then
    echo "Removing old app bundle..."
    rm -rf "${APP_DIR}"
fi

# Create app bundle structure
echo "Creating app bundle structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
echo "Copying executable..."
cp "${EXECUTABLE}" "${MACOS_DIR}/ScreenshotManagerApp"
chmod +x "${MACOS_DIR}/ScreenshotManagerApp"

# Copy app icon if it exists
if [ -f "${SCRIPT_DIR}/ScreenshotManager.icns" ]; then
    echo "Copying app icon..."
    cp "${SCRIPT_DIR}/ScreenshotManager.icns" "${RESOURCES_DIR}/ScreenshotManager.icns"
fi

# Create Info.plist
echo "Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ScreenshotManagerApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.screenshotmanager.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Screenshot Manager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>ScreenshotManager</string>
</dict>
</plist>
EOF

echo ""
echo "✅ App bundle created successfully!"
echo "📍 Location: ${APP_DIR}"
echo ""
echo "You can now:"
echo "  - Double-click to run: ${APP_BUNDLE}"
echo "  - Or run from terminal: open '${APP_BUNDLE}'"
echo ""
