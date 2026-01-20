import AppKit
import Foundation
import CoreGraphics
import ApplicationServices

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

@MainActor
final class PermissionChecker {
    // UserDefaults keys for permission state
    private static let skipPermissionCheckKey = "ScreenshotManager.skipPermissionCheck"
    private static let lastKnownGoodCaptureKey = "ScreenshotManager.lastKnownGoodCapture"

    /// Check if user chose to skip permission checks
    static var shouldSkipPermissionCheck: Bool {
        get { UserDefaults.standard.bool(forKey: skipPermissionCheckKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipPermissionCheckKey) }
    }

    /// Record that a capture succeeded (proves permissions work)
    static func recordSuccessfulCapture() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKnownGoodCaptureKey)
    }

    /// Check if we had a recent successful capture (within last hour)
    static var hadRecentSuccessfulCapture: Bool {
        let lastCapture = UserDefaults.standard.double(forKey: lastKnownGoodCaptureKey)
        guard lastCapture > 0 else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastCapture
        return elapsed < 3600 // Within last hour
    }

    /// Reset permission state (call when permissions definitely don't work)
    static func resetPermissionState() {
        shouldSkipPermissionCheck = false
        UserDefaults.standard.removeObject(forKey: lastKnownGoodCaptureKey)
    }

    enum PermissionType {
        case screenRecording
        case accessibility

        var name: String {
            switch self {
            case .screenRecording: return "Screen Recording"
            case .accessibility: return "Accessibility"
            }
        }

        var settingsURL: URL? {
            switch self {
            case .screenRecording:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        }
    }

    /// Check if screen recording permission is granted
    static func hasScreenRecordingPermission() -> Bool {
        // If user chose to skip checks and we had a recent successful capture, trust that
        if shouldSkipPermissionCheck && hadRecentSuccessfulCapture {
            return true
        }

        // Method 1: On macOS 13+, use CGPreflightScreenCaptureAccess
        if #available(macOS 13.0, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }
        }

        // Method 2: Try to actually capture a tiny region as a real test
        if let testImage = CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            []
        ) {
            if testImage.width > 0 && testImage.height > 0 {
                return true
            }
        }

        // Method 3: Check if we can get window list with window names
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if window[kCGWindowName as String] != nil {
                    return true
                }
            }
        }

        return false
    }

    /// Check if accessibility permission is granted
    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request screen recording permission (triggers system dialog via ScreenCaptureKit)
    static func requestScreenRecordingPermission() async {
        // CGWindowListCopyWindowInfo triggers the permission request
        _ = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)

        // Also use ScreenCaptureKit on macOS 13+ which shows a nicer dialog
        if #available(macOS 13.0, *) {
            #if canImport(ScreenCaptureKit)
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                // Expected if permission not granted yet
            }
            #endif
        }
    }

    /// Request accessibility permission (triggers system dialog)
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Check all required permissions
    static func checkPermissions() -> (screenRecording: Bool, accessibility: Bool) {
        return (hasScreenRecordingPermission(), hasAccessibilityPermission())
    }

    /// Request all missing permissions - triggers native macOS dialogs
    static func requestMissingPermissions() async {
        let hasScreen = hasScreenRecordingPermission()
        let hasAccessibility = hasAccessibilityPermission()

        // Request both at once - macOS will show its native dialogs
        if !hasAccessibility {
            requestAccessibilityPermission()
        }

        if !hasScreen {
            await requestScreenRecordingPermission()
        }
    }

    /// Open System Settings to the appropriate permission page
    static func openSystemSettings(for permission: PermissionType) {
        if let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
