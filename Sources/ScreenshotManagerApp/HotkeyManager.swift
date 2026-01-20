import Carbon
import Foundation

final class HotkeyManager {
    struct Hotkey {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private var hotkeys: [UInt32: Hotkey] = [:]
    private var eventHandler: EventHandlerRef?
    private var isInstalled = false

    init() {
        installHandler()
    }

    deinit {
        uninstallHandler()
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType("SHOT".fourCharCodeValue),
                                     id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            hotkeys[id] = Hotkey(id: id, keyCode: keyCode, modifiers: modifiers, handler: handler)
        }
    }

    private func installHandler() {
        guard !isInstalled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        // Use passRetained to ensure the manager stays alive while the handler is installed
        let retainedSelf = Unmanaged.passRetained(self)

        let status = InstallEventHandler(GetEventDispatcherTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(theEvent, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)

            if let userData = userData {
                // Use takeUnretainedValue since we manage the retain count manually
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let hotkey = manager.hotkeys[hkID.id] {
                    DispatchQueue.main.async {
                        hotkey.handler()
                    }
                    return noErr
                }
            }
            return CallNextEventHandler(nextHandler, theEvent)
        }, 1, &eventType, retainedSelf.toOpaque(), &eventHandler)

        if status == noErr {
            isInstalled = true
        } else {
            // Release if installation failed
            retainedSelf.release()
        }
    }

    private func uninstallHandler() {
        guard isInstalled else { return }

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
            // Release the retained self from installHandler
            Unmanaged.passUnretained(self).release()
        }
        hotkeys.removeAll()
        isInstalled = false
    }
}

private extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        if let data = self.data(using: .macOSRoman) {
            for (i, byte) in data.enumerated() {
                result += FourCharCode(byte) << (8 * (3 - i))
            }
        }
        return result
    }
}

