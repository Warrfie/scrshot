import AppKit
import Carbon

final class HotkeyManager {
    struct HotkeyDescriptor {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
    }

    static let defaultCaptureHotkey = HotkeyDescriptor(
        id: 1,
        keyCode: 19,
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var onCapture: (() -> Void)?

    private var captureHotkey = HotkeyManager.defaultCaptureHotkey

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    func start() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotkey(event: event)
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
        guard status == noErr else {
            AppLogger.shared.error(.hotkey, "failed to install hotkey handler: \(status)")
            return
        }
        AppLogger.shared.info(.hotkey, "installed hotkey handler")
        register(captureHotkey)
    }

    func setCaptureHotkey(_ descriptor: HotkeyDescriptor) {
        captureHotkey = descriptor
        reregisterHotkeys()
    }

    func stopCaptureHotkeys() {
        unregisterHotkeys()
        AppLogger.shared.info(.hotkey, "capture hotkey disabled")
    }

    func resumeCaptureHotkeys() {
        reregisterHotkeys()
    }

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        unregisterHotkeys()
    }

    private func register(_ descriptor: HotkeyDescriptor) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53534854), id: descriptor.id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            AppLogger.shared.error(.hotkey, "failed to register hotkey \(descriptor.id): \(status)")
            return
        }
        AppLogger.shared.info(.hotkey, "registered hotkey \(descriptor.id) keyCode=\(descriptor.keyCode) modifiers=\(descriptor.modifiers)")
        hotKeyRefs.append(hotKeyRef)
    }

    private func unregisterHotkeys() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    private func reregisterHotkeys() {
        guard eventHandler != nil else { return }
        unregisterHotkeys()
        register(captureHotkey)
    }

    private func handleHotkey(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return status
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch hotKeyID.id {
            case self.captureHotkey.id:
                self.onCapture?()
            default:
                break
            }
        }
        return noErr
    }
}
