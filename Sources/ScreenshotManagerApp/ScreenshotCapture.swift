import AppKit
import CoreGraphics
import Foundation

enum ScreenshotCapture {
    static func captureFullScreen() -> NSImage? {
        // Capture full screen - app windows will only appear if they're actually visible on top
        // No need to hide them, macOS window compositing handles visibility automatically
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        // Record successful capture to help with permission detection
        Task { @MainActor in
            PermissionChecker.recordSuccessfulCapture()
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    static func captureFrontmostWindow() -> NSImage? {
        guard let windowID = frontmostWindowID() else { return nil }
        let bounds = CGRect.null
        let imageOption: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        guard let cgImage = CGWindowListCreateImage(bounds, .optionIncludingWindow, windowID, imageOption) else { return nil }
        // Record successful capture to help with permission detection
        Task { @MainActor in
            PermissionChecker.recordSuccessfulCapture()
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private static func frontmostWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else { return nil }

        for info in infoList {
            guard let dict = info as? NSDictionary else { continue }
            guard let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else { continue }
            if let windowNumber = dict[kCGWindowNumber as String] as? NSNumber {
                return CGWindowID(windowNumber.uint32Value)
            }
        }
        return nil
    }
}

