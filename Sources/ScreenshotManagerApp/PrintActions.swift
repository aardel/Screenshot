import AppKit
import Foundation

enum PrintActions {
    static func printImage(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = image

        let printInfo = NSPrintInfo.shared
        printInfo.isVerticallyCentered = true
        printInfo.isHorizontallyCentered = true

        let op = NSPrintOperation(view: imageView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}

