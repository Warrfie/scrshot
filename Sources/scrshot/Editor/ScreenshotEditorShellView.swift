import AppKit
import SwiftUI

struct ScreenshotEditorShellView: View {
    @ObservedObject var viewModel: ScreenshotEditorShellViewModel
    private let canvasContent: AnyView
    private let ignoresTopSafeArea: Bool

    init(
        viewModel: ScreenshotEditorShellViewModel,
        editorViewController: ScreenshotEditorViewController,
        ignoresTopSafeArea: Bool = true
    ) {
        self.viewModel = viewModel
        self.ignoresTopSafeArea = ignoresTopSafeArea
        self.canvasContent = AnyView(
            ScreenshotEditorCanvasContainer(editorViewController: editorViewController)
        )
    }

    init<CanvasContent: View>(
        viewModel: ScreenshotEditorShellViewModel,
        ignoresTopSafeArea: Bool = true,
        @ViewBuilder canvasContent: () -> CanvasContent
    ) {
        self.viewModel = viewModel
        self.ignoresTopSafeArea = ignoresTopSafeArea
        self.canvasContent = AnyView(canvasContent())
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ScreenshotEditorToolbarView(viewModel: viewModel)

                canvasContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 15)
            .padding(.bottom, 10)
            .padding(.top, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(EditorTopSafeAreaModifier(isEnabled: ignoresTopSafeArea))
    }
}

private struct EditorTopSafeAreaModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.ignoresSafeArea(.container, edges: .top)
        } else {
            content
        }
    }
}

private struct ScreenshotEditorCanvasContainer: NSViewControllerRepresentable {
    let editorViewController: ScreenshotEditorViewController

    func makeNSViewController(context: Context) -> ScreenshotEditorViewController {
        editorViewController
    }

    func updateNSViewController(_ nsViewController: ScreenshotEditorViewController, context: Context) {}
}
