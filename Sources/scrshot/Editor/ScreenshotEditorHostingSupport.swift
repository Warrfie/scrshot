import AppKit
import SwiftUI

final class TitlebarlessHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = TitlebarlessHostingView(rootView: rootView)
    }
}

final class TitlebarlessHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        .init(top: 0, left: 0, bottom: 0, right: 0)
    }
}

final class FlippedDocumentContainerView: NSView {
    override var isFlipped: Bool { true }
}
