import AppKit

struct ScreenshotEditorScreenPlacement {
    let preferredDisplayID: CGDirectDisplayID?

    var visibleFrame: CGRect {
        if let preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func frameCenteredOnPreferredScreen(size: CGSize) -> CGRect {
        let visibleFrame = visibleFrame
        let clampedSize = CGSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
        return CGRect(
            x: round(visibleFrame.midX - clampedSize.width / 2),
            y: round(visibleFrame.midY - clampedSize.height / 2),
            width: clampedSize.width,
            height: clampedSize.height
        )
    }

    func center(_ window: NSWindow) {
        let visibleFrame = visibleFrame
        let currentSize = CGSize(
            width: min(window.frame.width, visibleFrame.width),
            height: min(window.frame.height, visibleFrame.height)
        )
        let origin = CGPoint(
            x: round(visibleFrame.midX - currentSize.width / 2),
            y: round(visibleFrame.midY - currentSize.height / 2)
        )
        window.setFrameOrigin(origin)
    }
}
