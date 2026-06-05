import AppKit

enum ScreenshotObscureStyle: String, CaseIterable {
    case blur
    case redact

    var title: String {
        switch self {
        case .blur:
            return "Blur"
        case .redact:
            return "Redact"
        }
    }
}

enum ScreenshotRectangleToolMode: String, CaseIterable {
    case highlight
    case blur
    case outline

    var title: String {
        switch self {
        case .highlight:
            return "Fill"
        case .blur:
            return "Blur"
        case .outline:
            return "No Fill"
        }
    }
}

enum ScreenshotLineStyle: String, CaseIterable {
    case solid
    case dashed
    case dotted
    case dashDotted

    var title: String {
        switch self {
        case .solid:
            return "Solid"
        case .dashed:
            return "Dash"
        case .dotted:
            return "Dot"
        case .dashDotted:
            return "Dash Dot"
        }
    }

    var dashPattern: [CGFloat] {
        switch self {
        case .solid:
            return []
        case .dashed:
            return [14, 10]
        case .dotted:
            return [2, 8]
        case .dashDotted:
            return [14, 8, 2, 8]
        }
    }
}

enum ScreenshotEditorTool: String, CaseIterable {
    case hand = "Hand"
    case crop = "Crop"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Rectangle"
    case detail = "Detail"
    case text = "Text"

    var symbolName: String {
        switch self {
        case .hand:
            return "hand.draw"
        case .crop:
            return "crop"
        case .arrow:
            return "arrow.up.right"
        case .line:
            return "pencil.tip"
        case .rectangle:
            return "rectangle"
        case .detail:
            return "plus.magnifyingglass"
        case .text:
            return "textformat"
        }
    }
}

enum ScreenshotAnnotationHandle {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case right
    case bottom
    case left
    case arrowStart
    case arrowEnd
}

func magnetizedLinePoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    let snapTolerance: CGFloat = 18

    if abs(deltaY) <= snapTolerance {
        return CGPoint(x: end.x, y: start.y)
    }
    if abs(deltaX) <= snapTolerance {
        return CGPoint(x: start.x, y: end.y)
    }
    return end
}
