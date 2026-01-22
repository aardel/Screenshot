import AppKit
import Foundation

// MARK: - Availability Notes
// NSSharingService.sharingServices(forItems:) is deprecated for building UI starting with macOS 14.
// We retain usage here for compatibility and discovery of messaging services.

enum ShareActions {
    /// Shows the macOS share sheet for sharing screenshots
    static func share(items: [URL], from view: NSView? = nil, relativeTo rect: NSRect? = nil) {
        guard !items.isEmpty else { return }
        
        let sharingPicker = NSSharingServicePicker(items: items)
        
        // If a view and rect are provided, show the picker relative to that view
        if let view = view, let rect = rect {
            sharingPicker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        } else {
            // Fallback: show from the current mouse location or center of screen
            if let window = NSApp.keyWindow,
               let contentView = window.contentView {
                let mouseLocation = NSEvent.mouseLocation
                let windowLocation = window.convertPoint(fromScreen: mouseLocation)
                let rect = NSRect(x: windowLocation.x, y: windowLocation.y, width: 1, height: 1)
                sharingPicker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
            }
        }
    }
    
    /// Get available sharing services for messaging apps
    static func availableMessagingServices(for items: [URL]) -> [(name: String, service: NSSharingService)] {
        guard !items.isEmpty else { return [] }
        var quick: [(name: String, service: NSSharingService)] = []
        if let messages = NSSharingService(named: .composeMessage) {
            quick.append((name: messages.title, service: messages))
        }
        if let airdrop = NSSharingService(named: .sendViaAirDrop) {
            quick.append((name: airdrop.title, service: airdrop))
        }
        return quick
    }
    
    /// Quick share to Messages
    static func shareToMessages(items: [URL]) {
        guard let service = NSSharingService(named: .composeMessage) else { return }
        service.perform(withItems: items)
    }
    
    /// Quick share to Mail
    static func shareToMail(items: [URL]) {
        guard let service = NSSharingService(named: .composeEmail) else { return }
        service.perform(withItems: items)
    }
    
    /// Share to a specific service by name
    static func shareToService(named serviceName: String, items: [URL]) {
        let lower = serviceName.lowercased()
        if lower.contains("airdrop"), let service = NSSharingService(named: .sendViaAirDrop) {
            service.perform(withItems: items)
            return
        }
        if lower.contains("message"), let service = NSSharingService(named: .composeMessage) {
            service.perform(withItems: items)
            return
        }
        if lower.contains("mail"), let service = NSSharingService(named: .composeEmail) {
            service.perform(withItems: items)
            return
        }
        // Fallback: show standard share sheet
        share(items: items)
    }
}

