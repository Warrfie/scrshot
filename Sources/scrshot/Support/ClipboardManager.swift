import AppKit
struct ClipboardManager {
    enum ClipboardError: LocalizedError {
        case failedToWrite
        var errorDescription: String? {
            switch self {
            case .failedToWrite:
                return "Unable to write the screenshot to the clipboard."
            }
        }
    }
    func copy(image: CGImage) throws {
        let size = NSSize(width: image.width, height: image.height)
        let nsImage = NSImage(cgImage: image, size: size)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([nsImage]) else {
            throw ClipboardError.failedToWrite
        }
    }
}
