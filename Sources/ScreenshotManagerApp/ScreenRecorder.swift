import AVFoundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

@available(macOS 13.0, *)
final class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var outputURL: URL?
    private var recordingIndicator: RecordingIndicatorWindow?
    private var recordingDisplay: SCDisplay?
    private var recordingWindow: SCWindow?
    private var recordingWindowID: CGWindowID?
    private var windowBorderOverlay: WindowBorderOverlay?
    private var windowTrackingTimer: Timer?
    private var windowPickerForRecording: WindowPickerForRecording?  // Keep strong reference

    var onRecordingFinished: ((URL?) -> Void)?

    func startRecordingScreen() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                print("No display found")
                await MainActor.run {
                    NSCursor.unhide()
                    NSCursor.arrow.set()
                }
                return
            }

            recordingDisplay = display
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let width = normalizedEven(Int(display.width))
            let height = normalizedEven(Int(display.height))
            await startRecording(with: filter, width: width, height: height)
        } catch {
            print("Failed to get shareable content: \(error)")
            // Restore cursor if permission was denied or error occurred
            await MainActor.run {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }
    }

    func startRecordingWindow() async {
        // Use WindowPicker to let user select a window
        let selectedWindowID = await pickWindowForRecording()
        
        guard let windowID = selectedWindowID else {
            // User cancelled
            await MainActor.run {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
            return
        }
        
        // Now start recording the selected window
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // Find the SCWindow for the selected window ID
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                print("Selected window not found")
                await MainActor.run {
                    NSCursor.unhide()
                    NSCursor.arrow.set()
                }
                return
            }
            
            recordingWindow = window
            recordingWindowID = window.windowID
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let (pixelWidth, pixelHeight) = recordingPixelSize(for: window)
            guard pixelWidth > 0, pixelHeight > 0 else {
                print("Invalid window size for recording: \(window.frame)")
                await MainActor.run {
                    NSCursor.unhide()
                    NSCursor.arrow.set()
                }
                return
            }
            
            // Show dotted border around the window and start tracking BEFORE recording starts
            await MainActor.run {
                showWindowBorder(for: window)
                startWindowTracking()
            }
            
            // Small delay to ensure border is visible before recording starts
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            await startRecording(with: filter, width: pixelWidth, height: pixelHeight)
        } catch {
            print("Failed to get shareable content: \(error)")
            // Restore cursor if permission was denied or error occurred
            await MainActor.run {
                stopWindowTracking()
                hideWindowBorder()
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }
    }
    
    private func pickWindowForRecording() async -> CGWindowID? {
        print("🎥 Starting window picker for recording...")
        return await withCheckedContinuation { [weak self] continuation in
            Task { @MainActor in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                print("🎥 Creating WindowPickerForRecording...")
                let picker = WindowPickerForRecording()
                self.windowPickerForRecording = picker  // Keep strong reference
                
                picker.start { [weak self] windowID in
                    print("🎥 Window picker returned: \(windowID?.description ?? "nil")")
                    // Clear the reference after completion
                    self?.windowPickerForRecording = nil
                    continuation.resume(returning: windowID)
                }
            }
        }
    }

    private func startRecording(with filter: SCContentFilter, width: Int, height: Int) async {
        guard !isRecording else { return }

        // Create output URL
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "Recording-\(timestamp).mp4"

        let folder = await MainActor.run {
            ScreenshotManagerApp.sharedLibrary?.watchedFolder
        }
        guard let folder = folder else { return }
        outputURL = folder.appendingPathComponent(filename)

        guard let outputURL = outputURL else { return }

        do {
            // Configure stream
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 5
            config.pixelFormat = kCVPixelFormatType_32BGRA

            // Setup asset writer
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: config.width,
                AVVideoHeightKey: config.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 10_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]

            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
            }

            // Create stream output
            streamOutput = RecordingStreamOutput()
            streamOutput?.assetWriter = assetWriter
            streamOutput?.videoInput = videoInput

            // Create and start stream
            stream = SCStream(filter: filter, configuration: config, delegate: nil)

            try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: DispatchQueue(label: "recording.queue"))

            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: .zero)

            try await stream?.startCapture()
            isRecording = true

            // Show recording indicator
            await MainActor.run {
                showRecordingIndicator()
            }

        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false

        do {
            try await stream?.stopCapture()
        } catch {
            print("Failed to stop capture: \(error)")
        }

        stream = nil

        // Wait for the asset writer to finish writing with a timeout
        guard let writer = assetWriter else { return }

        // Properly finalize the video - mark input finished before writer finishes
        videoInput?.markAsFinished()
        
        // Wait for writing to complete
        await writer.finishWriting()
        
        let finalURL = outputURL
        
        // Ensure the file is properly closed and finalized
        if writer.status == .completed {
            // File is ready - ensure it's flushed to disk
            if let outputURL = outputURL {
                // Force file system sync
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: outputURL.path)
            }
        } else if writer.status == .failed {
            print("Asset writer failed: \(writer.error?.localizedDescription ?? "Unknown error")")
            if let error = writer.error {
                print("Error details: \(error)")
            }
        }

        await MainActor.run {
            stopWindowTracking()
            hideRecordingIndicator()
            hideWindowBorder()
            recordingWindowID = nil
        }
        
        // Give the file system a moment to fully flush the file
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        await MainActor.run {
            // Notify that recording is complete so library can reload
            if let finalURL {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RecordingComplete"),
                    object: nil,
                    userInfo: ["url": finalURL]
                )
            }
            onRecordingFinished?(finalURL)
        }
    }

    private func showRecordingIndicator() {
        let indicator = RecordingIndicatorWindow()
        indicator.stopAction = { [weak self] in
            Task {
                await self?.stopRecording()
            }
        }
        indicator.orderFront(nil)
        recordingIndicator = indicator
    }

    private func hideRecordingIndicator() {
        recordingIndicator?.orderOut(nil)
        recordingIndicator = nil
    }
    
    private func showWindowBorder(for window: SCWindow) {
        // SCWindow.frame is in CoreGraphics coordinates (origin top-left)
        // NSWindow needs Cocoa coordinates (origin bottom-left)
        let cgFrame = window.frame
        
        // Convert from CG coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        // Find the main screen height for conversion
        guard let mainScreen = NSScreen.screens.first else { return }
        let mainScreenHeight = mainScreen.frame.height
        
        // Convert Y coordinate: CG has origin at top, Cocoa has origin at bottom
        let nsFrame = CGRect(
            x: cgFrame.origin.x,
            y: mainScreenHeight - cgFrame.origin.y - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
        
        let borderOverlay = WindowBorderOverlay(frame: nsFrame)
        borderOverlay.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        borderOverlay.orderFrontRegardless()
        windowBorderOverlay = borderOverlay
    }
    
    private func hideWindowBorder() {
        windowBorderOverlay?.orderOut(nil)
        windowBorderOverlay = nil
    }
    
    private func startWindowTracking() {
        // Stop any existing timer
        stopWindowTracking()
        
        guard let windowID = recordingWindowID else { return }
        
        // Create a timer to update the border position as the window moves
        // Run on main thread to ensure UI updates work correctly
        windowTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Query the current window frame using CoreGraphics
            if let windowInfo = self.getWindowInfo(for: windowID) {
                DispatchQueue.main.async {
                    self.updateWindowBorderPosition(to: windowInfo)
                }
            }
        }
        
        // Add timer to main run loop to ensure it fires
        if let timer = windowTrackingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func getWindowInfo(for windowID: CGWindowID) -> CGRect? {
        // Get window info using CoreGraphics
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let windowList = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let windowInfo = windowList.first,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        
        // Handle both CGFloat and Double types
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        
        if let xValue = boundsDict["X"] as? CGFloat {
            x = xValue
        } else if let xValue = boundsDict["X"] as? Double {
            x = CGFloat(xValue)
        } else {
            return nil
        }
        
        if let yValue = boundsDict["Y"] as? CGFloat {
            y = yValue
        } else if let yValue = boundsDict["Y"] as? Double {
            y = CGFloat(yValue)
        } else {
            return nil
        }
        
        if let widthValue = boundsDict["Width"] as? CGFloat {
            width = widthValue
        } else if let widthValue = boundsDict["Width"] as? Double {
            width = CGFloat(widthValue)
        } else {
            return nil
        }
        
        if let heightValue = boundsDict["Height"] as? CGFloat {
            height = heightValue
        } else if let heightValue = boundsDict["Height"] as? Double {
            height = CGFloat(heightValue)
        } else {
            return nil
        }
        
        // CGWindowListCopyWindowInfo returns coordinates in CoreGraphics space (origin top-left)
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func stopWindowTracking() {
        windowTrackingTimer?.invalidate()
        windowTrackingTimer = nil
    }
    
    private func updateWindowBorderPosition(to cgFrame: CGRect) {
        guard let borderOverlay = windowBorderOverlay else { return }
        
        // Convert from CG coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        // Find the screen that contains this window
        let cgPoint = CGPoint(x: cgFrame.midX, y: cgFrame.midY)
        var targetScreen: NSScreen?
        
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            // Convert CG point to NS coordinates for comparison
            let screenHeight = screen.frame.height
            let nsY = screenHeight - cgPoint.y
            let nsPoint = NSPoint(x: cgPoint.x, y: nsY)
            
            if NSPointInRect(nsPoint, screenFrame) {
                targetScreen = screen
                break
            }
        }
        
        guard let screen = targetScreen ?? NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height
        
        // Convert Y coordinate: CG has origin at top, Cocoa has origin at bottom
        // Also account for screen origin offset
        let nsFrame = CGRect(
            x: cgFrame.origin.x - screen.frame.origin.x,
            y: screenHeight - (cgFrame.origin.y - screen.frame.origin.y) - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
        
        // Update the window frame and force redraw
        borderOverlay.setFrame(nsFrame, display: true, animate: false)
        borderOverlay.contentView?.needsDisplay = true
    }
}

@available(macOS 13.0, *)
private extension ScreenRecorder {
    func normalizedEven(_ value: Int) -> Int {
        let adjusted = max(2, value)
        return adjusted % 2 == 0 ? adjusted : adjusted + 1
    }

    func recordingPixelSize(for window: SCWindow) -> (Int, Int) {
        let cgFrame = window.frame
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsFrame = CGRect(
            x: cgFrame.origin.x,
            y: mainScreenHeight - cgFrame.origin.y - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(nsFrame) }) ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2.0
        let width = normalizedEven(Int((cgFrame.width * scale).rounded(.up)))
        let height = normalizedEven(Int((cgFrame.height * scale).rounded(.up)))
        return (width, height)
    }
}

@available(macOS 13.0, *)
private class RecordingStreamOutput: NSObject, SCStreamOutput {
    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    private var firstSampleTime: CMTime?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstSampleTime == nil {
            firstSampleTime = timestamp
        }

        // Adjust timestamp relative to first sample
        guard let firstTime = firstSampleTime else { return }
        let adjustedTime = CMTimeSubtract(timestamp, firstTime)

        if let adjustedBuffer = adjustTimestamp(of: sampleBuffer, to: adjustedTime) {
            videoInput.append(adjustedBuffer)
        }
    }

    private func adjustTimestamp(of sampleBuffer: CMSampleBuffer, to newTimestamp: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newTimestamp,
            decodeTimeStamp: .invalid
        )

        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )

        return newBuffer
    }
}

// Recording indicator window (red dot in menu bar area)
final class RecordingIndicatorWindow: NSWindow {
    var stopAction: (() -> Void)?

    init() {
        let size = CGSize(width: 140, height: 32)
        let screenFrame = NSScreen.main?.frame ?? .zero
        let origin = CGPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height - 5)

        super.init(contentRect: CGRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = true

        let contentView = RecordingIndicatorView(frame: CGRect(origin: .zero, size: size))
        contentView.stopAction = { [weak self] in
            self?.stopAction?()
        }
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
}

final class RecordingIndicatorView: NSView {
    var stopAction: (() -> Void)?
    private var pulseTimer: Timer?
    private var isPulseOn = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startPulse()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pulseTimer?.invalidate()
    }

    private func startPulse() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.isPulseOn.toggle()
            self?.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        stopAction?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background pill
        NSColor.black.withAlphaComponent(0.8).setFill()
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
        bgPath.fill()

        // Red recording dot
        let dotSize: CGFloat = 12
        let dotRect = CGRect(x: 12, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
        let dotColor = isPulseOn ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(0.5)
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        // "Recording" text
        let text = "Recording"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(x: 30, y: (bounds.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        text.draw(in: textRect, withAttributes: attributes)

        // Stop button
        let stopText = "Stop"
        let stopAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let stopSize = stopText.size(withAttributes: stopAttributes)
        let stopRect = CGRect(x: bounds.width - stopSize.width - 12, y: (bounds.height - stopSize.height) / 2, width: stopSize.width, height: stopSize.height)
        stopText.draw(in: stopRect, withAttributes: stopAttributes)
    }
}

// Window border overlay for recording
final class WindowBorderOverlay: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        let borderView = WindowBorderView(frame: CGRect(origin: .zero, size: frame.size))
        contentView = borderView
    }
    
    override var canBecomeKey: Bool { false }
}

final class WindowBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw dotted border around the window
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        borderPath.lineWidth = 3
        
        // Create dashed line pattern
        let dashPattern: [CGFloat] = [8, 4]  // 8 points dash, 4 points gap
        borderPath.setLineDash(dashPattern, count: 2, phase: 0)
        
        // Draw border in system blue color
        NSColor.systemBlue.setStroke()
        borderPath.stroke()
    }
}

// Window picker specifically for recording - returns window ID instead of capturing
@available(macOS 13.0, *)
final class WindowPickerForRecording {
    private var overlayWindows: [WindowPickerOverlay] = []
    private var highlightWindow: WindowHighlightOverlayForRecording?
    private var completion: ((CGWindowID?) -> Void)?
    private var hoveredWindowID: CGWindowID?
    private var eventMonitor: Any?

    func start(completion: @escaping (CGWindowID?) -> Void) {
        print("🎥 WindowPickerForRecording.start() called")
        self.completion = completion

        // Create overlay on each screen
        print("🎥 Creating overlays for \(NSScreen.screens.count) screens")
        for screen in NSScreen.screens {
            let overlay = WindowPickerOverlay(screen: screen)
            overlay.onMouseMoved = { [weak self] point in
                self?.handleMouseMoved(to: point)
            }
            overlay.onMouseClicked = { [weak self] point in
                self?.handleMouseClicked(at: point)
            }
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
            print("🎥 Created overlay for screen: \(screen.frame)")
        }

        // Monitor for ESC key
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                print("🎥 ESC key pressed, cancelling")
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        // Activate app to receive events
        NSApp.activate(ignoringOtherApps: true)
        print("🎥 Window picker UI should be visible now")
    }

    private func handleMouseMoved(to point: NSPoint) {
        print("🎥 Mouse moved to: \(point)")
        // Ensure point is on a screen
        guard NSScreen.screens.contains(where: { NSPointInRect(point, $0.frame) }) else { 
            print("🎥 Point not on any screen")
            return 
        }

        // Find window under cursor
        let windowID = windowUnderPoint(point)
        print("🎥 Window under point: \(windowID?.description ?? "nil")")

        if windowID != hoveredWindowID {
            hoveredWindowID = windowID
            updateHighlight()
        }
    }

    private func handleMouseClicked(at point: NSPoint) {
        print("🎥 Mouse clicked at: \(point)")
        guard let windowID = hoveredWindowID else {
            print("🎥 No window hovered, cancelling")
            finish(with: nil)
            return
        }

        print("🎥 Returning selected window ID: \(windowID)")
        // Return the selected window ID
        finish(with: windowID)
    }

    private func windowUnderPoint(_ point: NSPoint) -> CGWindowID? {
        // Get all on-screen windows
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Convert NSPoint to CGPoint (flip Y coordinate for CG)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        for windowInfo in windowList {
            // Skip our own overlay windows
            guard let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == 0 else { continue } // Only normal windows

            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else { continue }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)

            if windowFrame.contains(cgPoint) {
                if let windowNumber = windowInfo[kCGWindowNumber as String] as? Int {
                    // Skip our own windows
                    let isOurWindow = overlayWindows.contains { Int($0.windowNumber) == windowNumber } ||
                                      (highlightWindow != nil && Int(highlightWindow!.windowNumber) == windowNumber)
                    if !isOurWindow {
                        return CGWindowID(windowNumber)
                    }
                }
            }
        }

        return nil
    }

    private func updateHighlight() {
        // Remove existing highlight
        highlightWindow?.orderOut(nil)
        highlightWindow = nil

        guard let windowID = hoveredWindowID else { return }

        // Get window frame
        guard let windowFrame = frameForWindow(windowID) else { return }

        // Convert CG coordinates to NS coordinates
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsFrame = CGRect(
            x: windowFrame.origin.x,
            y: screenHeight - windowFrame.origin.y - windowFrame.height,
            width: windowFrame.width,
            height: windowFrame.height
        )

        // Create highlight window with blue border (matching recording border style)
        highlightWindow = WindowHighlightOverlayForRecording(frame: nsFrame)
        highlightWindow?.orderFront(nil)
    }

    private func frameForWindow(_ windowID: CGWindowID) -> CGRect? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let windowList = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let windowInfo = windowList.first,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let width = boundsDict["Width"],
              let height = boundsDict["Height"] else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func finish(with windowID: CGWindowID?) {
        print("🎥 WindowPickerForRecording.finish() called with: \(windowID?.description ?? "nil")")
        cleanup()
        print("🎥 Calling completion handler...")
        completion?(windowID)
        print("🎥 Completion handler called")
    }

    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        highlightWindow?.orderOut(nil)
        highlightWindow = nil

        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    deinit {
        cleanup()
    }
}

// Blue highlight overlay for recording window picker
final class WindowHighlightOverlayForRecording: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = WindowHighlightViewForRecording(frame: CGRect(origin: .zero, size: frame.size))
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
}

final class WindowHighlightViewForRecording: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw blue dotted border (matching recording border style)
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        borderPath.lineWidth = 3

        // Dashed line pattern
        let dashPattern: [CGFloat] = [8, 4]  // 8 points dash, 4 points gap
        borderPath.setLineDash(dashPattern, count: 2, phase: 0)

        // Draw border in system blue color (same as recording border)
        NSColor.systemBlue.setStroke()
        borderPath.stroke()
    }
}
