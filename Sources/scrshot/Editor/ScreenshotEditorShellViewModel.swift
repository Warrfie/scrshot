import AppKit
import SwiftUI

enum ScreenshotEditorInspectorKind {
    case none
    case crop
    case arrow
    case line
    case rectangle
    case detail
    case text
}

private extension ScreenshotEditorTool {
    var previewInspectorKind: ScreenshotEditorInspectorKind {
        switch self {
        case .hand:
            return .none
        case .crop:
            return .crop
        case .arrow:
            return .arrow
        case .line:
            return .line
        case .rectangle:
            return .rectangle
        case .detail:
            return .detail
        case .text:
            return .text
        }
    }
}

@MainActor
final class ScreenshotEditorShellViewModel: ObservableObject {
    @Published var selectedTool: ScreenshotEditorTool = .hand
    @Published var inspectorKind: ScreenshotEditorInspectorKind = .none
    @Published var annotationColor: NSColor = .systemRed
    @Published var rectangleColor: NSColor = .systemRed
    @Published var arrowStrokeWidth: CGFloat = 8
    @Published var rectangleMode: ScreenshotRectangleToolMode = .blur
    @Published var detailScale: CGFloat = 2
    @Published var detailShape: ScreenshotDetailShape = .oval
    @Published var lineStyle: ScreenshotLineStyle = .solid
    @Published var textSize: CGFloat = 28
    @Published var textAlignment: NSTextAlignment = .left

    var onCancel: (() -> Void)?
    var onDone: ((CGImage) -> Void)?
    var onCloseWindow: (() -> Void)?
    var onMinimizeWindow: (() -> Void)?
    var onZoomWindow: (() -> Void)?

    private weak var editorViewController: ScreenshotEditorViewController?

    func bind(to editorViewController: ScreenshotEditorViewController) {
        self.editorViewController = editorViewController
    }

    func apply(_ state: ScreenshotEditorShellState) {
        selectedTool = state.selectedTool
        inspectorKind = state.inspectorKind
        annotationColor = state.annotationColor
        rectangleColor = state.rectangleColor
        arrowStrokeWidth = state.arrowStrokeWidth
        rectangleMode = state.rectangleMode
        detailScale = state.detailScale
        detailShape = state.detailShape
        lineStyle = state.lineStyle
        textSize = state.textSize
        textAlignment = state.textAlignment
    }

    func selectTool(_ tool: ScreenshotEditorTool) {
        if let editorViewController {
            editorViewController.selectTool(tool)
        } else {
            selectedTool = tool
            inspectorKind = tool.previewInspectorKind
        }
    }

    func setAnnotationColor(_ color: NSColor) {
        if let editorViewController {
            editorViewController.setAnnotationColor(color)
        } else {
            annotationColor = color
        }
    }

    func setRectangleColor(_ color: NSColor) {
        if let editorViewController {
            editorViewController.setRectangleColor(color)
        } else {
            rectangleColor = color
        }
    }

    func setArrowStrokeWidth(_ width: CGFloat) {
        let allowsZero = inspectorKind == .rectangle || inspectorKind == .detail
        let clampedWidth = min(max(width, allowsZero ? 0 : 2), 24)
        if let editorViewController {
            editorViewController.setArrowStrokeWidth(clampedWidth)
        } else {
            arrowStrokeWidth = clampedWidth
        }
    }

    func setDetailShape(_ shape: ScreenshotDetailShape) {
        if let editorViewController {
            editorViewController.setDetailShape(shape)
        } else {
            detailShape = shape
        }
    }

    func setRectangleMode(_ mode: ScreenshotRectangleToolMode) {
        if let editorViewController {
            editorViewController.setRectangleMode(mode)
        } else {
            rectangleMode = mode
        }
    }

    func setLineStyle(_ style: ScreenshotLineStyle) {
        if let editorViewController {
            editorViewController.setLineStyle(style)
        } else {
            lineStyle = style
        }
    }

    func setTextSize(_ size: CGFloat) {
        if let editorViewController {
            editorViewController.setTextSize(size)
        } else {
            textSize = size
        }
    }

    func setTextAlignment(_ alignment: NSTextAlignment) {
        if let editorViewController {
            editorViewController.setTextAlignment(alignment)
        } else {
            textAlignment = alignment
        }
    }

    func fit() {
        editorViewController?.fitToWindowAction(nil)
    }

    func cancel() {
        onCancel?()
    }

    func done() {
        guard let image = editorViewController?.renderedImage() else {
            NSSound.beep()
            return
        }
        onDone?(image)
    }

    func closeWindow() {
        onCloseWindow?()
    }

    func minimizeWindow() {
        onMinimizeWindow?()
    }

    func zoomWindow() {
        onZoomWindow?()
    }
}

struct ScreenshotEditorShellState {
    var selectedTool: ScreenshotEditorTool
    var inspectorKind: ScreenshotEditorInspectorKind
    var annotationColor: NSColor
    var rectangleColor: NSColor
    var arrowStrokeWidth: CGFloat
    var rectangleMode: ScreenshotRectangleToolMode
    var detailScale: CGFloat
    var detailShape: ScreenshotDetailShape
    var lineStyle: ScreenshotLineStyle
    var textSize: CGFloat
    var textAlignment: NSTextAlignment
}
