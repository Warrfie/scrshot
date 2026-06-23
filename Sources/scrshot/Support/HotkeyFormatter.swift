import Carbon
import Foundation

enum HotkeyFormatter {
    static func string(for descriptor: HotkeyManager.HotkeyDescriptor) -> String {
        modifierSymbols(for: descriptor.modifiers) + keyName(for: descriptor.keyCode)
    }

    static func readableString(for descriptor: HotkeyManager.HotkeyDescriptor) -> String {
        let components = readableModifiers(for: descriptor.modifiers) + [keyName(for: descriptor.keyCode)]
        return components
            .filter { !$0.isEmpty }
            .joined(separator: " + ")
    }

    private static func modifierSymbols(for modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    private static func readableModifiers(for modifiers: UInt32) -> [String] {
        var names: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { names.append("⌘") }
        if modifiers & UInt32(controlKey) != 0 { names.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { names.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { names.append("Shift") }
        return names
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let specialKeyName = specialKeyName(for: keyCode) {
            return specialKeyName
        }
        if let translatedKeyName = translatedKeyName(for: keyCode) {
            return translatedKeyName
        }
        return "Key \(keyCode)"
    }

    private static func translatedKeyName(for keyCode: UInt32) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        return data.withUnsafeBytes { rawBuffer in
            guard let keyboardLayout = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var unicodeScalars = [UniChar](repeating: 0, count: 4)

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                unicodeScalars.count,
                &actualLength,
                &unicodeScalars
            )

            guard status == noErr, actualLength > 0 else {
                return nil
            }

            return String(utf16CodeUnits: unicodeScalars, count: actualLength)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }
    }

    private static func specialKeyName(for keyCode: UInt32) -> String? {
        switch keyCode {
        case 36:
            return "↩"
        case 48:
            return "⇥"
        case 49:
            return "Space"
        case 51:
            return "⌫"
        case 53:
            return "⎋"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        default:
            return nil
        }
    }
}
