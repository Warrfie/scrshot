import AppKit
import CoreImage

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
    case redact

    var title: String {
        switch self {
        case .highlight:
            return "Tint"
        case .blur:
            return "Blur"
        case .redact:
            return "Black"
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

private func drawCGImageInTopLeftCoordinates(_ image: CGImage, in rect: CGRect) {
    guard let cgContext = NSGraphicsContext.current?.cgContext else {
        return
    }

    cgContext.saveGState()
    cgContext.translateBy(x: rect.minX, y: rect.maxY)
    cgContext.scaleBy(x: 1, y: -1)
    cgContext.draw(image, in: CGRect(origin: .zero, size: rect.size))
    cgContext.restoreGState()
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

struct ScreenshotEditorAnnotation: Identifiable {
    enum Kind: Equatable {
        case arrow
        case line
        case highlight
        case obscure
        case detail
        case text
    }

    let id: UUID
    let kind: Kind
    var rect: CGRect
    var text: String?
    var color: NSColor
    var strokeWidth: CGFloat
    var fontSize: CGFloat
    var textAlignment: NSTextAlignment
    var obscureStyle: ScreenshotObscureStyle
    var lineStyle: ScreenshotLineStyle
    var fillOpacity: CGFloat
    var showsTextBackground: Bool
    var textBackgroundColor: NSColor
    var detailSourcePoint: CGPoint
    var detailScale: CGFloat

    static func arrow(from start: CGPoint, to end: CGPoint, color: NSColor) -> ScreenshotEditorAnnotation {
        ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .arrow,
            rect: CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y),
            text: nil,
            color: color,
            strokeWidth: 8,
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: 0,
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: .zero,
            detailScale: 2
        )
    }

    static func highlight(_ rect: CGRect, color: NSColor, fillOpacity: CGFloat = 0.24) -> ScreenshotEditorAnnotation {
        ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .highlight,
            rect: rect.standardized,
            text: nil,
            color: color,
            strokeWidth: 3,
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: min(max(fillOpacity, 0.05), 1),
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: .zero,
            detailScale: 2
        )
    }

    static func line(from start: CGPoint, to end: CGPoint, color: NSColor) -> ScreenshotEditorAnnotation {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let isHorizontal = abs(deltaX) >= abs(deltaY)
        let targetX = isHorizontal ? end.x : start.x
        let targetY = isHorizontal ? start.y : end.y
        return ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .line,
            rect: CGRect(x: start.x, y: start.y, width: targetX - start.x, height: targetY - start.y),
            text: nil,
            color: color,
            strokeWidth: 8,
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: 0,
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: .zero,
            detailScale: 2
        )
    }

    static func obscure(_ rect: CGRect, style: ScreenshotObscureStyle) -> ScreenshotEditorAnnotation {
        ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .obscure,
            rect: rect.standardized,
            text: nil,
            color: .black,
            strokeWidth: 0,
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: style,
            lineStyle: .solid,
            fillOpacity: 1,
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: .zero,
            detailScale: 2
        )
    }

    static func detail(sourcePoint: CGPoint, bubbleCenter: CGPoint, color: NSColor, scale: CGFloat) -> ScreenshotEditorAnnotation {
        let size = CGSize(width: 140, height: 140)
        let origin = CGPoint(x: bubbleCenter.x - size.width / 2, y: bubbleCenter.y - size.height / 2)
        return ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .detail,
            rect: CGRect(origin: origin, size: size),
            text: nil,
            color: color,
            strokeWidth: 3,
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: 0,
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: sourcePoint,
            detailScale: min(max(scale, 1.5), 6)
        )
    }

    static func text(
        _ text: String,
        at point: CGPoint,
        color: NSColor,
        fontSize: CGFloat,
        alignment: NSTextAlignment,
        showsBackground: Bool,
        backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.55)
    ) -> ScreenshotEditorAnnotation {
        ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .text,
            rect: CGRect(origin: point, size: NSSize(width: 260, height: max(56, fontSize + 28))),
            text: text,
            color: color,
            strokeWidth: 0,
            fontSize: fontSize,
            textAlignment: alignment,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: 0,
            showsTextBackground: showsBackground,
            textBackgroundColor: backgroundColor,
            detailSourcePoint: .zero,
            detailScale: 2
        )
    }

    var startPoint: CGPoint {
        rect.origin
    }

    var endPoint: CGPoint {
        CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height)
    }

    var centerPoint: CGPoint {
        CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
    }

    private var clampedDetailScale: CGFloat {
        min(max(detailScale, 1.5), 6)
    }

    private var detailSourceRect: CGRect {
        let bubbleRect = rect.standardized
        let sampleWidth = max(bubbleRect.width / clampedDetailScale, 24)
        let sampleHeight = max(bubbleRect.height / clampedDetailScale, 24)
        return CGRect(
            x: detailSourcePoint.x - sampleWidth / 2,
            y: detailSourcePoint.y - sampleHeight / 2,
            width: sampleWidth,
            height: sampleHeight
        )
    }

    var selectionBounds: CGRect {
        switch kind {
        case .arrow, .line:
            return CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            ).insetBy(dx: -14, dy: -14)
        case .highlight, .obscure, .text:
            return rect.standardized
        case .detail:
            let bubbleRect = rect.standardized
            let sourceRect = detailSourceRect
            return bubbleRect.union(sourceRect).insetBy(dx: -8, dy: -8)
        }
    }

    func draw(baseImage: CGImage? = nil) {
        switch kind {
        case .arrow:
            drawArrow()
        case .line:
            drawLine()
        case .highlight, .obscure:
            drawRectangle(baseImage: baseImage)
        case .detail:
            drawDetail(baseImage: baseImage)
        case .text:
            drawText()
        }
    }

    func translatedBy(dx: CGFloat, dy: CGFloat) -> ScreenshotEditorAnnotation {
        var adjusted = self
        adjusted.rect = adjusted.rect.offsetBy(dx: dx, dy: dy)
        if adjusted.kind == .detail {
            adjusted.detailSourcePoint = adjusted.detailSourcePoint.offsetBy(dx: dx, dy: dy)
        }
        return adjusted
    }

    func exportAdjusted(forCanvasHeight canvasHeight: CGFloat) -> ScreenshotEditorAnnotation {
        var adjusted = self

        switch kind {
        case .arrow:
            let convertedStart = CGPoint(x: startPoint.x, y: canvasHeight - startPoint.y)
            let convertedEnd = CGPoint(x: endPoint.x, y: canvasHeight - endPoint.y)
            adjusted.rect = CGRect(
                x: convertedStart.x,
                y: convertedStart.y,
                width: convertedEnd.x - convertedStart.x,
                height: convertedEnd.y - convertedStart.y
            )
        case .line:
            let convertedStart = CGPoint(x: startPoint.x, y: canvasHeight - startPoint.y)
            let convertedEnd = CGPoint(x: endPoint.x, y: canvasHeight - endPoint.y)
            adjusted.rect = CGRect(
                x: convertedStart.x,
                y: convertedStart.y,
                width: convertedEnd.x - convertedStart.x,
                height: convertedEnd.y - convertedStart.y
            )
        case .text:
            let boxRect = rect.standardized
            adjusted.rect = CGRect(
                x: boxRect.minX,
                y: canvasHeight - boxRect.maxY,
                width: boxRect.width,
                height: boxRect.height
            )
        case .highlight, .obscure, .detail:
            break
        }

        return adjusted
    }

    func drawSelection(scale: CGFloat, showsHandles: Bool) {
        let selectionPath = selectionPath(scale: scale)
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        let dash: [CGFloat] = [8 / scale, 6 / scale]
        selectionPath.setLineDash(dash, count: dash.count, phase: 0)
        selectionPath.lineWidth = 2 / scale
        selectionPath.stroke()

        guard showsHandles else { return }

        for handleRect in visibleHandleRects(scale: scale).values {
            let handlePath = NSBezierPath(
                roundedRect: handleRect,
                xRadius: 3 / scale,
                yRadius: 3 / scale
            )
            NSColor.white.setFill()
            handlePath.fill()
            NSColor.controlAccentColor.setStroke()
            handlePath.lineWidth = 1 / scale
            handlePath.stroke()
        }
    }

    func deleteButtonRect(scale: CGFloat) -> CGRect {
        let bounds = selectionBounds
        let size: CGFloat = max(16 / scale, 18)
        let inset: CGFloat = max(6 / scale, 6)
        return CGRect(
            x: bounds.maxX - size / 2,
            y: bounds.minY - size / 2 - inset,
            width: size,
            height: size
        )
    }

    func handleRects(scale: CGFloat) -> [ScreenshotAnnotationHandle: CGRect] {
        let handleSize: CGFloat = 12 / scale
        switch kind {
        case .arrow, .line:
            return [
                .arrowStart: CGRect(x: startPoint.x - handleSize / 2, y: startPoint.y - handleSize / 2, width: handleSize, height: handleSize),
                .arrowEnd: CGRect(x: endPoint.x - handleSize / 2, y: endPoint.y - handleSize / 2, width: handleSize, height: handleSize)
            ]
        case .highlight, .obscure, .text, .detail:
            let bounds = rect.standardized
            return [
                .topLeft: CGRect(x: bounds.minX - handleSize / 2, y: bounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .topRight: CGRect(x: bounds.maxX - handleSize / 2, y: bounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .bottomLeft: CGRect(x: bounds.minX - handleSize / 2, y: bounds.maxY - handleSize / 2, width: handleSize, height: handleSize),
                .bottomRight: CGRect(x: bounds.maxX - handleSize / 2, y: bounds.maxY - handleSize / 2, width: handleSize, height: handleSize)
            ]
        }
    }

    func handle(at point: CGPoint, scale: CGFloat) -> ScreenshotAnnotationHandle? {
        handleRects(scale: scale).first(where: { $0.value.contains(point) })?.key
    }

    func visibleHandleRects(scale: CGFloat) -> [ScreenshotAnnotationHandle: CGRect] {
        switch kind {
        case .arrow, .line:
            return [:]
        case .highlight, .obscure, .text, .detail:
            return handleRects(scale: scale)
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        switch kind {
        case .arrow, .line:
            let lineHitWidth: CGFloat = 10
            let distance = point.distanceToSegment(start: startPoint, end: endPoint)
            return distance <= lineHitWidth || selectionBounds.contains(point)
        case .highlight, .obscure, .text:
            return rect.standardized.insetBy(dx: -6, dy: -6).contains(point)
        case .detail:
            let bubbleRect = rect.standardized
            let lineDistance = point.distanceToSegment(start: detailSourcePoint, end: bubbleRect.centerPoint)
            let sourceRect = detailSourceRect.insetBy(dx: -6, dy: -6)
            return bubbleRect.insetBy(dx: -6, dy: -6).contains(point) || sourceRect.contains(point) || lineDistance <= 8
        }
    }

    mutating func move(by delta: CGPoint, clampedTo bounds: CGRect) {
        switch kind {
        case .arrow, .line:
            let newStart = startPoint.offsetBy(dx: delta.x, dy: delta.y).clamped(to: bounds)
            let newEnd = endPoint.offsetBy(dx: delta.x, dy: delta.y).clamped(to: bounds)
            rect = CGRect(x: newStart.x, y: newStart.y, width: newEnd.x - newStart.x, height: newEnd.y - newStart.y)
        case .highlight, .obscure, .text:
            let current = rect.standardized
            let maxX = bounds.maxX - current.width
            let maxY = bounds.maxY - current.height
            let origin = CGPoint(
                x: min(max(current.minX + delta.x, bounds.minX), maxX),
                y: min(max(current.minY + delta.y, bounds.minY), maxY)
            )
            rect = CGRect(origin: origin, size: current.size)
        case .detail:
            let current = rect.standardized
            let maxX = bounds.maxX - current.width
            let maxY = bounds.maxY - current.height
            let origin = CGPoint(
                x: min(max(current.minX + delta.x, bounds.minX), maxX),
                y: min(max(current.minY + delta.y, bounds.minY), maxY)
            )
            rect = CGRect(origin: origin, size: current.size)
            detailSourcePoint = detailSourcePoint.offsetBy(dx: delta.x, dy: delta.y).clamped(to: bounds)
        }
    }

    mutating func resize(using handle: ScreenshotAnnotationHandle, to point: CGPoint, clampedTo bounds: CGRect) {
        switch kind {
        case .arrow:
            let clampedPoint = point.clamped(to: bounds)
            switch handle {
            case .arrowStart:
                rect = CGRect(x: clampedPoint.x, y: clampedPoint.y, width: endPoint.x - clampedPoint.x, height: endPoint.y - clampedPoint.y)
            case .arrowEnd:
                rect = CGRect(x: startPoint.x, y: startPoint.y, width: clampedPoint.x - startPoint.x, height: clampedPoint.y - startPoint.y)
            default:
                break
            }
        case .line:
            let clampedPoint = point.clamped(to: bounds)
            switch handle {
            case .arrowStart:
                let snappedPoint = ScreenshotEditorCanvasView.magnetizedLinePoint(from: endPoint, to: clampedPoint)
                rect = CGRect(x: snappedPoint.x, y: snappedPoint.y, width: endPoint.x - snappedPoint.x, height: endPoint.y - snappedPoint.y)
            case .arrowEnd:
                let snappedPoint = ScreenshotEditorCanvasView.magnetizedLinePoint(from: startPoint, to: clampedPoint)
                rect = CGRect(x: startPoint.x, y: startPoint.y, width: snappedPoint.x - startPoint.x, height: snappedPoint.y - startPoint.y)
            default:
                break
            }
        case .highlight, .obscure, .text, .detail:
            let current = rect.standardized
            let clampedPoint = point.clamped(to: bounds)
            var minX = current.minX
            var minY = current.minY
            var maxX = current.maxX
            var maxY = current.maxY

            switch handle {
            case .topLeft:
                minX = clampedPoint.x
                minY = clampedPoint.y
            case .topRight:
                maxX = clampedPoint.x
                minY = clampedPoint.y
            case .bottomLeft:
                minX = clampedPoint.x
                maxY = clampedPoint.y
            case .bottomRight:
                maxX = clampedPoint.x
                maxY = clampedPoint.y
            default:
                break
            }

            let minimumSide: CGFloat
            switch kind {
            case .text:
                minimumSide = 32
            case .detail:
                minimumSide = 60
            default:
                minimumSide = 24
            }
            let width = max(minimumSide, abs(maxX - minX))
            let height = max(minimumSide, abs(maxY - minY))
            rect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: width, height: height)
        }
    }

    private func drawArrow() {
        let start = startPoint
        let end = endPoint
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let headLength: CGFloat = max(14, strokeWidth * 3.2)
        let headAngle: CGFloat = .pi / 7

        let left = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.move(to: end)
        head.line(to: right)
        head.lineWidth = strokeWidth
        head.lineCapStyle = .round
        head.stroke()
    }

    private func drawLine() {
        let path = NSBezierPath()
        path.move(to: startPoint)
        path.line(to: endPoint)
        path.lineWidth = strokeWidth
        let dash = lineStyle.dashPattern
        path.lineCapStyle = dash.isEmpty ? .round : .butt
        if !dash.isEmpty {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        color.setStroke()
        path.stroke()
    }

    private func selectionPath(scale: CGFloat) -> NSBezierPath {
        switch kind {
        case .arrow, .line:
            let start = startPoint
            let end = endPoint
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(hypot(dx, dy), 0.0001)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            let parallelInset = max(12 / scale, strokeWidth * 0.9)
            let perpendicularInset = max(10 / scale, strokeWidth * 1.4)
            let extensionVector = CGPoint(x: dx / length * perpendicularInset, y: dy / length * perpendicularInset)
            let normalVector = CGPoint(x: normal.x * parallelInset, y: normal.y * parallelInset)

            let p1 = CGPoint(x: start.x - extensionVector.x + normalVector.x, y: start.y - extensionVector.y + normalVector.y)
            let p2 = CGPoint(x: end.x + extensionVector.x + normalVector.x, y: end.y + extensionVector.y + normalVector.y)
            let p3 = CGPoint(x: end.x + extensionVector.x - normalVector.x, y: end.y + extensionVector.y - normalVector.y)
            let p4 = CGPoint(x: start.x - extensionVector.x - normalVector.x, y: start.y - extensionVector.y - normalVector.y)

            let path = NSBezierPath()
            path.move(to: p1)
            path.line(to: p2)
            path.line(to: p3)
            path.line(to: p4)
            path.close()
            return path
        case .highlight, .obscure, .text, .detail:
            return NSBezierPath(rect: selectionBounds)
        }
    }

    private func drawRectangle(baseImage: CGImage?) {
        let boxRect = rect.standardized.integral
        guard boxRect.width > 0, boxRect.height > 0 else { return }

        switch kind {
        case .highlight:
            let path = NSBezierPath(rect: boxRect)
            color.withAlphaComponent(fillOpacity).setFill()
            path.fill()
            color.withAlphaComponent(max(0.45, min(fillOpacity + 0.35, 1))).setStroke()
            path.lineWidth = strokeWidth
            path.stroke()
        case .obscure:
            switch obscureStyle {
            case .redact:
                let path = NSBezierPath(roundedRect: boxRect, xRadius: 8, yRadius: 8)
                NSColor.black.setFill()
                path.fill()
            case .blur:
                guard let baseImage,
                      let blurredImage = Self.blurredImage(from: baseImage, in: boxRect) else {
                    let fallback = NSBezierPath(roundedRect: boxRect, xRadius: 8, yRadius: 8)
                    NSColor.black.withAlphaComponent(0.75).setFill()
                    fallback.fill()
                    return
                }
                drawCGImageInTopLeftCoordinates(blurredImage, in: boxRect)
            }
        case .arrow, .line, .text, .detail:
            break
        }
    }

    private func drawDetail(baseImage: CGImage?) {
        guard let baseImage else { return }
        let bubbleRect = rect.standardized.integral
        guard bubbleRect.width > 20, bubbleRect.height > 20 else { return }

        let sampleRect = detailSourceRect
            .intersection(CGRect(origin: .zero, size: CGSize(width: baseImage.width, height: baseImage.height)))

        let bubbleCenter = bubbleRect.centerPoint
        let connector = NSBezierPath()
        connector.move(to: detailSourcePoint)
        connector.line(to: bubbleCenter)
        color.withAlphaComponent(0.9).setStroke()
        connector.lineWidth = max(strokeWidth, 2)
        connector.stroke()

        let sourceMarkerRect = detailSourceRect.integral
        let sourceMarker = NSBezierPath(ovalIn: sourceMarkerRect)
        NSColor.windowBackgroundColor.withAlphaComponent(0.2).setFill()
        sourceMarker.fill()
        color.setStroke()
        sourceMarker.lineWidth = max(strokeWidth, 2)
        sourceMarker.stroke()

        guard let zoomedImage = Self.croppedImage(from: baseImage, in: sampleRect) else { return }

        let clipPath = NSBezierPath(ovalIn: bubbleRect)
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        drawCGImageInTopLeftCoordinates(zoomedImage, in: bubbleRect)
        NSGraphicsContext.restoreGraphicsState()

        let bubblePath = NSBezierPath(ovalIn: bubbleRect)
        NSColor.windowBackgroundColor.withAlphaComponent(0.18).setFill()
        bubblePath.fill()
        color.setStroke()
        bubblePath.lineWidth = max(strokeWidth, 2)
        bubblePath.stroke()
    }

    private func drawText() {
        let boxRect = rect.standardized
        let fontSize = max(12, self.fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        let attributed = NSAttributedString(string: text ?? "", attributes: attributes)
        let textInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let contentRect = boxRect.insetBy(dx: textInsets.left, dy: textInsets.top)

        if showsTextBackground {
            let background = NSBezierPath(roundedRect: boxRect, xRadius: 8, yRadius: 8)
            textBackgroundColor.setFill()
            background.fill()
        }

        attributed.draw(with: contentRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func blurredImage(from baseImage: CGImage, in targetRect: CGRect) -> CGImage? {
        let sourceRect = CGRect(
            x: targetRect.minX,
            y: CGFloat(baseImage.height) - targetRect.maxY,
            width: targetRect.width,
            height: targetRect.height
        ).integral.intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))

        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }

        let ciImage = CIImage(cgImage: baseImage).cropped(to: sourceRect)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(8.0, forKey: kCIInputRadiusKey)
        guard let outputImage = filter.outputImage?.cropped(to: sourceRect) else { return nil }
        return ciContext.createCGImage(outputImage, from: sourceRect)
    }

    private static func croppedImage(from baseImage: CGImage, in targetRect: CGRect) -> CGImage? {
        let pixelAlignedRect = CGRect(
            x: round(targetRect.minX),
            y: round(targetRect.minY),
            width: max(round(targetRect.width), 1),
            height: max(round(targetRect.height), 1)
        )
        let sourceRect = pixelAlignedRect.intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }
        return baseImage.cropping(to: sourceRect)
    }

    private static let ciContext = CIContext(options: nil)
}

extension ScreenshotEditorAnnotation: Equatable {
    static func == (lhs: ScreenshotEditorAnnotation, rhs: ScreenshotEditorAnnotation) -> Bool {
        lhs.id == rhs.id &&
        lhs.kind == rhs.kind &&
        lhs.rect == rhs.rect &&
        lhs.text == rhs.text &&
        lhs.strokeWidth == rhs.strokeWidth &&
        lhs.fontSize == rhs.fontSize &&
        lhs.textAlignment == rhs.textAlignment &&
        lhs.obscureStyle == rhs.obscureStyle &&
        lhs.lineStyle == rhs.lineStyle &&
        lhs.fillOpacity == rhs.fillOpacity &&
        lhs.showsTextBackground == rhs.showsTextBackground &&
        lhs.detailSourcePoint == rhs.detailSourcePoint &&
        lhs.detailScale == rhs.detailScale &&
        lhs.color.matches(rhs.color) &&
        lhs.textBackgroundColor.matches(rhs.textBackgroundColor)
    }
}

@MainActor
final class ScreenshotEditorDocument {
    private struct Snapshot: Equatable {
        let annotations: [ScreenshotEditorAnnotation]
        let selectedAnnotationID: UUID?
        let cropRect: CGRect?
    }

    private(set) var image: CGImage
    private(set) var annotations: [ScreenshotEditorAnnotation] = []
    private(set) var selectedAnnotationID: UUID?
    private(set) var cropRect: CGRect?
    private let editorUndoManager = UndoManager()
    private var pendingInteraction: (snapshot: Snapshot, actionName: String)?

    init(image: CGImage) {
        self.image = image
        editorUndoManager.groupsByEvent = false
    }

    var undoManager: UndoManager {
        editorUndoManager
    }

    var canvasSize: NSSize {
        NSSize(width: image.width, height: image.height)
    }

    var focusRect: CGRect {
        cropRect ?? CGRect(origin: .zero, size: canvasSize)
    }

    var selectedAnnotation: ScreenshotEditorAnnotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first(where: { $0.id == selectedAnnotationID })
    }

    var canUndo: Bool {
        undoManager.canUndo
    }

    var canRedo: Bool {
        undoManager.canRedo
    }

    func addAnnotation(_ annotation: ScreenshotEditorAnnotation) {
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
    }

    func selectAnnotation(id: UUID?) {
        selectedAnnotationID = id
    }

    func annotation(withID id: UUID) -> ScreenshotEditorAnnotation? {
        annotations.first(where: { $0.id == id })
    }

    func annotation(at point: CGPoint) -> ScreenshotEditorAnnotation? {
        annotations.reversed().first(where: { $0.contains(point) })
    }

    func updateSelectedColor(_ color: NSColor) {
        guard let index = selectedIndex else { return }
        annotations[index].color = color
    }

    func updateSelectedStrokeWidth(_ strokeWidth: CGFloat) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .arrow || annotations[index].kind == .line || annotations[index].kind == .highlight else { return }
        annotations[index].strokeWidth = min(max(strokeWidth, 2), 24)
    }

    func updateText(_ text: String, for annotationID: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == annotationID }) else { return }
        annotations[index].text = text
        selectedAnnotationID = annotationID
    }

    func updateTextLayout(for annotationID: UUID, size: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == annotationID }) else { return }
        guard annotations[index].kind == .text else { return }
        let current = annotations[index].rect.standardized
        annotations[index].rect = CGRect(origin: current.origin, size: size)
        selectedAnnotationID = annotationID
    }

    func updateSelectedTextFontSize(_ fontSize: CGFloat) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .text else { return }
        annotations[index].fontSize = min(max(fontSize, 12), 96)
    }

    func updateSelectedTextAlignment(_ alignment: NSTextAlignment) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .text else { return }
        annotations[index].textAlignment = alignment
    }

    func updateSelectedTextBackground(_ showsBackground: Bool) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .text else { return }
        annotations[index].showsTextBackground = showsBackground
    }

    func updateSelectedTextBackgroundColor(_ color: NSColor) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .text else { return }
        annotations[index].textBackgroundColor = color
    }

    func updateSelectedObscureStyle(_ style: ScreenshotObscureStyle) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .obscure else { return }
        annotations[index].obscureStyle = style
    }

    func updateSelectedLineStyle(_ style: ScreenshotLineStyle) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .line else { return }
        annotations[index].lineStyle = style
    }

    func updateSelectedFillOpacity(_ opacity: CGFloat) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .highlight else { return }
        annotations[index].fillOpacity = min(max(opacity, 0.05), 1)
    }

    func updateSelectedDetailScale(_ scale: CGFloat) {
        guard let index = selectedIndex else { return }
        guard annotations[index].kind == .detail else { return }
        annotations[index].detailScale = min(max(scale, 1.5), 6)
    }

    func moveSelected(by delta: CGPoint) {
        guard let index = selectedIndex else { return }
        annotations[index].move(by: delta, clampedTo: CGRect(origin: .zero, size: canvasSize))
    }

    func resizeSelected(using handle: ScreenshotAnnotationHandle, to point: CGPoint) {
        guard let index = selectedIndex else { return }
        annotations[index].resize(using: handle, to: point, clampedTo: CGRect(origin: .zero, size: canvasSize))
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        annotations.removeAll(where: { $0.id == selectedAnnotationID })
        self.selectedAnnotationID = nil
    }

    func deleteAnnotation(id: UUID) {
        annotations.removeAll(where: { $0.id == id })
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
    }

    func renderedImage() -> CGImage? {
        guard let cropRect else {
            return makeBitmapImage(from: image, size: canvasSize, annotations: annotations)
        }
        guard let croppedBaseImage = image.cropping(to: cropRect.integral) else {
            return nil
        }
        let croppedAnnotations = annotations
            .filter { $0.selectionBounds.intersects(cropRect) }
            .map { $0.translatedBy(dx: -cropRect.minX, dy: -cropRect.minY) }
        return makeBitmapImage(from: croppedBaseImage, size: cropRect.size, annotations: croppedAnnotations)
    }

    func applyCrop(_ rect: CGRect) -> Bool {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let cropRect = rect.standardized.integral.intersection(bounds)
        guard cropRect.width > 2, cropRect.height > 2 else {
            return false
        }
        self.cropRect = cropRect
        selectedAnnotationID = nil
        return true
    }

    func clearCrop() {
        cropRect = nil
    }

    func moveCrop(by delta: CGPoint) {
        guard let cropRect else { return }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let maxX = bounds.maxX - cropRect.width
        let maxY = bounds.maxY - cropRect.height
        let origin = CGPoint(
            x: min(max(cropRect.minX + delta.x, bounds.minX), maxX),
            y: min(max(cropRect.minY + delta.y, bounds.minY), maxY)
        )
        self.cropRect = CGRect(origin: origin, size: cropRect.size)
    }

    func resizeCrop(using handle: ScreenshotAnnotationHandle, to point: CGPoint) {
        guard let cropRect else { return }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let current = cropRect.standardized
        let clampedPoint = point.clamped(to: bounds)

        var minX = current.minX
        var minY = current.minY
        var maxX = current.maxX
        var maxY = current.maxY

        switch handle {
        case .topLeft:
            minX = clampedPoint.x
            minY = clampedPoint.y
        case .top:
            minY = clampedPoint.y
        case .topRight:
            maxX = clampedPoint.x
            minY = clampedPoint.y
        case .right:
            maxX = clampedPoint.x
        case .bottomLeft:
            minX = clampedPoint.x
            maxY = clampedPoint.y
        case .bottom:
            maxY = clampedPoint.y
        case .bottomRight:
            maxX = clampedPoint.x
            maxY = clampedPoint.y
        case .left:
            minX = clampedPoint.x
        default:
            return
        }

        self.cropRect = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: max(24, abs(maxX - minX)),
            height: max(24, abs(maxY - minY))
        ).intersection(bounds)
    }

    func performUndoableChange(actionName: String, _ changes: () -> Void) {
        let snapshot = makeSnapshot()
        changes()
        registerUndo(from: snapshot, actionName: actionName)
    }

    func beginInteraction(actionName: String) {
        guard pendingInteraction == nil else { return }
        pendingInteraction = (makeSnapshot(), actionName)
    }

    func endInteraction() {
        guard let interaction = pendingInteraction else { return }
        pendingInteraction = nil
        registerUndo(from: interaction.snapshot, actionName: interaction.actionName)
    }

    func cancelInteraction() {
        pendingInteraction = nil
    }

    func undo() {
        undoManager.undo()
    }

    func redo() {
        undoManager.redo()
    }

    private var selectedIndex: Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex(where: { $0.id == selectedAnnotationID })
    }

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            annotations: annotations,
            selectedAnnotationID: selectedAnnotationID,
            cropRect: cropRect
        )
    }

    private func apply(snapshot: Snapshot) {
        annotations = snapshot.annotations
        selectedAnnotationID = snapshot.selectedAnnotationID
        cropRect = snapshot.cropRect
    }

    private func registerUndo(from snapshot: Snapshot, actionName: String) {
        let current = makeSnapshot()
        guard snapshot != current else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(snapshot: snapshot, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    private func restore(snapshot: Snapshot, actionName: String) {
        let current = makeSnapshot()
        apply(snapshot: snapshot)
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(snapshot: current, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    private func makeBitmapImage(
        from baseImage: CGImage,
        size: NSSize,
        annotations: [ScreenshotEditorAnnotation]
    ) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 32
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: size.height)
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()
        drawCGImageInTopLeftCoordinates(baseImage, in: CGRect(origin: .zero, size: size))
        for annotation in annotations where annotation.kind != .arrow && annotation.kind != .line && annotation.kind != .text {
            annotation.draw(baseImage: baseImage)
        }
        NSGraphicsContext.restoreGraphicsState()

        for annotation in annotations where annotation.kind == .arrow || annotation.kind == .line || annotation.kind == .text {
            annotation.exportAdjusted(forCanvasHeight: size.height).draw(baseImage: baseImage)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}

private final class InlineTextEditorView: NSView {
    let textView: NSTextView
    private let padding = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    override var isFlipped: Bool { true }

    init(frame frameRect: CGRect, color: NSColor, fontSize: CGFloat, alignment: NSTextAlignment, showsBackground: Bool, backgroundColor: NSColor) {
        let textContainer = NSTextContainer(size: NSSize(width: max(frameRect.width - 24, 80), height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let textView = NSTextView(frame: frameRect.insetBy(dx: 12, dy: 8), textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = false
        textView.allowsUndo = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        self.textView = textView
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        addSubview(textView)
        updateStyle(color: color, fontSize: fontSize, alignment: alignment, showsBackground: showsBackground, backgroundColor: backgroundColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateStyle(color: NSColor, fontSize: CGFloat, alignment: NSTextAlignment, showsBackground: Bool, backgroundColor: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        if textView.textStorage?.length ?? 0 > 0 {
            textView.textStorage?.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        }
        layer?.backgroundColor = showsBackground ? backgroundColor.cgColor : NSColor.clear.cgColor
    }

    func updateFrame(origin: CGPoint, width: CGFloat, height: CGFloat) {
        frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        textView.frame = bounds.insetBy(dx: padding.left, dy: padding.top)
        textView.textContainer?.containerSize = NSSize(width: max(bounds.width - padding.left - padding.right, 80), height: .greatestFiniteMagnitude)
    }

    func measuredHeight() -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return max(56, textView.font?.pointSize ?? 24)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return ceil(max(usedHeight + padding.top + padding.bottom, (textView.font?.pointSize ?? 24) + padding.top + padding.bottom + 8))
    }
}

@MainActor
final class ScreenshotEditorCanvasView: NSView, NSTextViewDelegate {
    var tool: ScreenshotEditorTool = .arrow
    var activeColor: NSColor = .systemRed
    var activeArrowStrokeWidth: CGFloat = 8
    var activeRectangleMode: ScreenshotRectangleToolMode = .blur
    var activeLineStyle: ScreenshotLineStyle = .solid
    var activeHighlightOpacity: CGFloat = 0.24
    var activeDetailScale: CGFloat = 2
    var activeTextFontSize: CGFloat = 28
    var activeTextAlignment: NSTextAlignment = .left
    var activeTextShowsBackground = true
    var activeTextBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.55)
    var onImageChanged: (() -> Void)?
    var onSelectionChanged: ((ScreenshotEditorAnnotation?) -> Void)?
    var onCropChanged: ((CGRect?) -> Void)?
    var onRequestFitToWindow: (() -> Void)?
    var onRequestFitToRect: ((CGRect) -> Void)?
    var onRequestMagnify: ((CGPoint, CGFloat) -> Void)?

    private let document: ScreenshotEditorDocument
    private var cropDragStart: CGPoint?
    private var cropDragCurrent: CGPoint?
    private var cropMoveLastPoint: CGPoint?
    private var cropActiveHandle: ScreenshotAnnotationHandle?
    private var hoveredAnnotationID: UUID?
    private var isHoveringCrop = false
    private var creationDragStart: CGPoint?
    private var creationDragCurrent: CGPoint?
    private var movingLastPoint: CGPoint?
    private var activeHandle: ScreenshotAnnotationHandle?
    private var handPanLastPoint: CGPoint?
    private var trackingArea: NSTrackingArea?
    private var inlineTextEditorView: InlineTextEditorView?
    private var inlineTextAnnotationID: UUID?
    private var pendingTextActivationAnnotationID: UUID?
    private var inlineTextKeyEventMonitor: Any?
    private var isHoveringSelectedDeleteButton = false
    private var isHoveringCropDeleteButton = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var undoManager: UndoManager? { document.undoManager }

    var selectedAnnotation: ScreenshotEditorAnnotation? {
        document.selectedAnnotation
    }

    var cropRect: CGRect? {
        document.cropRect
    }

    init(document: ScreenshotEditorDocument) {
        self.document = document
        super.init(frame: CGRect(origin: .zero, size: document.canvasSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    func updateCanvasSize() {
        frame = CGRect(origin: .zero, size: document.canvasSize)
        needsDisplay = true
        invalidateCursorState()
    }

    func applyColor(_ color: NSColor) {
        activeColor = color
        if document.selectedAnnotation != nil {
            document.performUndoableChange(actionName: "Change Color") {
                document.updateSelectedColor(color)
            }
            notifyDocumentDidChange()
        }
        updateInlineTextEditorAppearance()
    }

    func applyArrowStrokeWidth(_ strokeWidth: CGFloat) {
        activeArrowStrokeWidth = min(max(strokeWidth, 2), 24)
        if document.selectedAnnotation?.kind == .arrow || document.selectedAnnotation?.kind == .line || document.selectedAnnotation?.kind == .highlight {
            document.performUndoableChange(actionName: "Change Stroke Width") {
                document.updateSelectedStrokeWidth(activeArrowStrokeWidth)
            }
            notifyDocumentDidChange()
        }
    }

    func applyTextFontSize(_ fontSize: CGFloat) {
        activeTextFontSize = min(max(fontSize, 12), 96)
        if document.selectedAnnotation?.kind == .text {
            document.performUndoableChange(actionName: "Change Text Size") {
                document.updateSelectedTextFontSize(activeTextFontSize)
            }
            syncInlineTextEditorLayout()
            notifyDocumentDidChange()
        }
    }

    func applyTextAlignment(_ alignment: NSTextAlignment) {
        activeTextAlignment = alignment
        if document.selectedAnnotation?.kind == .text {
            document.performUndoableChange(actionName: "Change Text Alignment") {
                document.updateSelectedTextAlignment(alignment)
            }
            updateInlineTextEditorAppearance()
            notifyDocumentDidChange()
        }
    }

    func applyTextBackground(_ showsBackground: Bool) {
        activeTextShowsBackground = showsBackground
        if document.selectedAnnotation?.kind == .text {
            document.performUndoableChange(actionName: "Toggle Text Background") {
                document.updateSelectedTextBackground(showsBackground)
            }
            updateInlineTextEditorAppearance()
            notifyDocumentDidChange()
        }
    }

    func applyTextBackgroundColor(_ color: NSColor) {
        activeTextBackgroundColor = color
        if document.selectedAnnotation?.kind == .text {
            document.performUndoableChange(actionName: "Change Text Background Color") {
                document.updateSelectedTextBackgroundColor(color)
            }
            updateInlineTextEditorAppearance()
            notifyDocumentDidChange()
        }
    }

    func applyRectangleMode(_ mode: ScreenshotRectangleToolMode) {
        activeRectangleMode = mode
        if document.selectedAnnotation?.kind == .obscure {
            let style: ScreenshotObscureStyle = mode == .blur ? .blur : .redact
            document.performUndoableChange(actionName: "Change Rectangle Mode") {
                document.updateSelectedObscureStyle(style)
            }
            notifyDocumentDidChange()
        }
    }

    func applyLineStyle(_ style: ScreenshotLineStyle) {
        activeLineStyle = style
        if document.selectedAnnotation?.kind == .line {
            document.performUndoableChange(actionName: "Change Line Style") {
                document.updateSelectedLineStyle(style)
            }
            notifyDocumentDidChange()
        }
    }

    func applyHighlightOpacity(_ opacity: CGFloat) {
        activeHighlightOpacity = min(max(opacity, 0.05), 1)
        if document.selectedAnnotation?.kind == .highlight {
            document.performUndoableChange(actionName: "Change Rectangle Opacity") {
                document.updateSelectedFillOpacity(activeHighlightOpacity)
            }
            notifyDocumentDidChange()
        }
    }

    func applyDetailScale(_ scale: CGFloat) {
        activeDetailScale = min(max(scale, 1.5), 6)
        if document.selectedAnnotation?.kind == .detail {
            document.performUndoableChange(actionName: "Change Detail Scale") {
                document.updateSelectedDetailScale(activeDetailScale)
            }
            notifyDocumentDidChange()
        }
    }

    func editSelectedText() {
        guard let selected = document.selectedAnnotation, selected.kind == .text else { return }
        beginInlineTextEditing(annotationID: selected.id)
    }

    func updateText(_ text: String, for annotationID: UUID) {
        document.performUndoableChange(actionName: "Edit Text") {
            document.updateText(text, for: annotationID)
        }
        notifyDocumentDidChange()
    }

    func deleteSelection() {
        finishInlineTextEditing(commit: false)
        document.performUndoableChange(actionName: "Delete Annotation") {
            document.deleteSelectedAnnotation()
        }
        notifyDocumentDidChange()
        invalidateCursorState()
    }

    func clearCrop() {
        guard document.cropRect != nil else { return }
        document.performUndoableChange(actionName: "Clear Crop") {
            document.clearCrop()
        }
        notifyDocumentDidChange()
        invalidateCursorState()
    }

    func makeRenderedImage() -> CGImage? {
        finishInlineTextEditing(commit: true)
        return document.renderedImage()
    }

    private func beginInlineTextEditing(annotationID: UUID) {
        guard let annotation = document.annotation(withID: annotationID), annotation.kind == .text else { return }

        finishInlineTextEditing(commit: true)

        let editor = InlineTextEditorView(
            frame: annotation.rect.standardized,
            color: annotation.color,
            fontSize: annotation.fontSize,
            alignment: annotation.textAlignment,
            showsBackground: annotation.showsTextBackground,
            backgroundColor: annotation.textBackgroundColor
        )
        editor.textView.delegate = self
        editor.textView.string = annotation.text ?? ""
        addSubview(editor)
        inlineTextEditorView = editor
        inlineTextAnnotationID = annotationID
        document.selectAnnotation(id: annotationID)
        syncInlineTextEditorLayout()
        needsDisplay = true
        installInlineTextKeyEventMonitor()
        activateInlineTextEditor(editor.textView)
        onSelectionChanged?(document.selectedAnnotation)
    }

    private func finishInlineTextEditing(commit: Bool) {
        guard let inlineTextAnnotationID, let editor = inlineTextEditorView else { return }

        removeInlineTextKeyEventMonitor()

        defer {
            inlineTextEditorView = nil
            self.inlineTextAnnotationID = nil
            editor.removeFromSuperview()
            needsDisplay = true
            invalidateCursorState()
        }

        guard commit else { return }

        let text = editor.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            document.performUndoableChange(actionName: "Delete Text") {
                document.deleteAnnotation(id: inlineTextAnnotationID)
            }
            notifyDocumentDidChange()
            return
        }

        document.performUndoableChange(actionName: "Edit Text") {
            document.updateText(text, for: inlineTextAnnotationID)
            if let annotation = document.annotation(withID: inlineTextAnnotationID) {
                let size = CGSize(width: annotation.rect.width, height: editor.measuredHeight())
                document.updateTextLayout(for: inlineTextAnnotationID, size: size)
            }
        }
        notifyDocumentDidChange()
    }

    private func syncInlineTextEditorLayout() {
        guard let inlineTextAnnotationID,
              let editor = inlineTextEditorView,
              let annotation = document.annotation(withID: inlineTextAnnotationID) else { return }

        editor.updateStyle(
            color: annotation.color,
            fontSize: annotation.fontSize,
            alignment: annotation.textAlignment,
            showsBackground: annotation.showsTextBackground,
            backgroundColor: annotation.textBackgroundColor
        )
        let height = editor.measuredHeight()
        let size = CGSize(width: annotation.rect.width, height: height)
        document.updateTextLayout(for: inlineTextAnnotationID, size: size)
        let updatedRect = document.annotation(withID: inlineTextAnnotationID)?.rect.standardized ?? annotation.rect.standardized
        editor.updateFrame(origin: updatedRect.origin, width: updatedRect.width, height: updatedRect.height)
        onImageChanged?()
        onSelectionChanged?(document.selectedAnnotation)
        needsDisplay = true
    }

    private func installInlineTextKeyEventMonitor() {
        guard inlineTextKeyEventMonitor == nil else { return }
        inlineTextKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleInlineTextKeyEventIfNeeded(event) ? nil : event
        }
    }

    private func removeInlineTextKeyEventMonitor() {
        guard let inlineTextKeyEventMonitor else { return }
        NSEvent.removeMonitor(inlineTextKeyEventMonitor)
        self.inlineTextKeyEventMonitor = nil
    }

    @discardableResult
    private func handleInlineTextKeyEventIfNeeded(_ event: NSEvent) -> Bool {
        guard let editor = inlineTextEditorView,
              let window,
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control) else {
            return false
        }
        if let eventWindow = event.window, eventWindow !== window {
            return false
        }

        if event.keyCode == 53 {
            finishInlineTextEditing(commit: true)
            window.makeFirstResponder(self)
            return true
        }

        if window.firstResponder !== editor.textView {
            activateInlineTextEditor(editor.textView)
        }
        editor.textView.keyDown(with: event)
        return true
    }

    @discardableResult
    func dispatchInlineTextKeyEventForTesting(_ event: NSEvent) -> Bool {
        handleInlineTextKeyEventIfNeeded(event)
    }

    private func updateInlineTextEditorAppearance() {
        guard let inlineTextAnnotationID,
              let annotation = document.annotation(withID: inlineTextAnnotationID),
              let editor = inlineTextEditorView else { return }
        editor.updateStyle(
            color: annotation.color,
            fontSize: annotation.fontSize,
            alignment: annotation.textAlignment,
            showsBackground: annotation.showsTextBackground,
            backgroundColor: annotation.textBackgroundColor
        )
        needsDisplay = true
    }

    private func activateInlineTextEditor(_ textView: NSTextView) {
        func focus(_ textView: NSTextView) {
            NSApp.activate(ignoringOtherApps: true)
            guard let window = textView.window, textView.superview != nil else { return }
            window.makeKeyAndOrderFront(nil)
            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        }

        focus(textView)

        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            focus(textView)
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                focus(textView)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak textView] in
            guard let textView else { return }
            focus(textView)
        }
    }

    private func activatePendingTextEditorIfNeeded() {
        guard let annotationID = pendingTextActivationAnnotationID else { return }
        pendingTextActivationAnnotationID = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.beginInlineTextEditing(annotationID: annotationID)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = boundedPoint(convert(event.locationInWindow, from: nil))
        if let editor = inlineTextEditorView, !editor.frame.contains(point) {
            finishInlineTextEditing(commit: true)
        }

        if let selected = document.selectedAnnotation,
           selected.deleteButtonRect(scale: interactionScale).contains(point) {
            deleteSelection()
            return
        }

        if let cropRect = document.cropRect,
           cropDeleteButtonRect(for: cropRect, scale: interactionScale).contains(point) {
            clearCrop()
            return
        }

        if tool == .crop {
            window?.makeFirstResponder(self)
            if let handle = cropHandle(at: point) {
                document.beginInteraction(actionName: "Resize Crop")
                cropActiveHandle = handle
                needsDisplay = true
                invalidateCursorState()
                return
            }
            if let cropRect = document.cropRect, cropRect.contains(point) {
                document.beginInteraction(actionName: "Move Crop")
                cropMoveLastPoint = point
                needsDisplay = true
                invalidateCursorState()
                return
            }
            document.beginInteraction(actionName: "Apply Crop")
            cropDragStart = point
            cropDragCurrent = point
            needsDisplay = true
            invalidateCursorState()
            return
        }

        if tool == .hand {
            window?.makeFirstResponder(self)
            handPanLastPoint = point
            invalidateCursorState()
            return
        }

        if let selected = document.selectedAnnotation, let handle = selected.handle(at: point, scale: interactionScale) {
            window?.makeFirstResponder(self)
            document.beginInteraction(actionName: "Resize Annotation")
            activeHandle = handle
            onSelectionChanged?(selected)
            needsDisplay = true
            return
        }

        if let hitAnnotation = document.annotation(at: point) {
            document.selectAnnotation(id: hitAnnotation.id)
            onSelectionChanged?(document.selectedAnnotation)
            needsDisplay = true

            if tool == .text, hitAnnotation.kind == .text, event.clickCount >= 2 {
                beginInlineTextEditing(annotationID: hitAnnotation.id)
                return
            }

            window?.makeFirstResponder(self)
            document.beginInteraction(actionName: "Move Annotation")
            movingLastPoint = point
            return
        }

        document.selectAnnotation(id: nil)
        onSelectionChanged?(nil)

        switch tool {
        case .hand:
            break
        case .arrow, .line, .rectangle, .detail:
            window?.makeFirstResponder(self)
            creationDragStart = point
            creationDragCurrent = point
        case .text:
            let annotation = ScreenshotEditorAnnotation.text(
                "",
                at: point,
                color: activeColor,
                fontSize: activeTextFontSize,
                alignment: activeTextAlignment,
                showsBackground: activeTextShowsBackground,
                backgroundColor: activeTextBackgroundColor
            )
            document.performUndoableChange(actionName: "Add Text") {
                document.addAnnotation(annotation)
            }
            notifyDocumentDidChange()
            pendingTextActivationAnnotationID = annotation.id
        case .crop:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = boundedPoint(convert(event.locationInWindow, from: nil))

        if cropDragStart != nil {
            cropDragCurrent = point
            needsDisplay = true
            invalidateCursorState()
            return
        }

        if let cropActiveHandle {
            document.resizeCrop(using: cropActiveHandle, to: point)
            onImageChanged?()
            onCropChanged?(document.cropRect)
            needsDisplay = true
            invalidateCursorState()
            return
        }

        if let lastPoint = handPanLastPoint {
            panViewport(by: CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y))
            handPanLastPoint = point
            invalidateCursorState()
            return
        }

        if let lastPoint = cropMoveLastPoint {
            let delta = CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)
            document.moveCrop(by: delta)
            cropMoveLastPoint = point
            onImageChanged?()
            onCropChanged?(document.cropRect)
            needsDisplay = true
            invalidateCursorState()
            return
        }

        if let activeHandle {
            document.resizeSelected(using: activeHandle, to: point)
            onImageChanged?()
            onSelectionChanged?(document.selectedAnnotation)
            needsDisplay = true
            return
        }

        if let lastPoint = movingLastPoint, document.selectedAnnotation != nil {
            let delta = CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)
            document.moveSelected(by: delta)
            movingLastPoint = point
            onImageChanged?()
            onSelectionChanged?(document.selectedAnnotation)
            needsDisplay = true
            return
        }

        if creationDragStart != nil {
            creationDragCurrent = point
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = boundedPoint(convert(event.locationInWindow, from: nil))

        defer {
            cropDragStart = nil
            cropDragCurrent = nil
            cropMoveLastPoint = nil
            cropActiveHandle = nil
            creationDragStart = nil
            creationDragCurrent = nil
            movingLastPoint = nil
            activeHandle = nil
            handPanLastPoint = nil
            needsDisplay = true
            invalidateCursorState()
        }

        if let cropDragStart {
            if document.applyCrop(CGRect(
                x: min(cropDragStart.x, point.x),
                y: min(cropDragStart.y, point.y),
                width: abs(point.x - cropDragStart.x),
                height: abs(point.y - cropDragStart.y)
            )) {
                document.endInteraction()
                notifyDocumentDidChange()
                if let cropRect = document.cropRect {
                    onRequestFitToRect?(cropRect)
                }
            } else {
                document.cancelInteraction()
                NSSound.beep()
            }
            return
        }

        guard let creationDragStart else {
            document.endInteraction()
            notifyDocumentDidChange()
            activatePendingTextEditorIfNeeded()
            return
        }

        switch tool {
        case .arrow:
            guard hypot(point.x - creationDragStart.x, point.y - creationDragStart.y) > 8 else {
                return
            }
            var arrow = ScreenshotEditorAnnotation.arrow(from: creationDragStart, to: point, color: activeColor)
            arrow.strokeWidth = activeArrowStrokeWidth
            document.performUndoableChange(actionName: "Add Arrow") {
                document.addAnnotation(arrow)
            }
        case .line:
            guard max(abs(point.x - creationDragStart.x), abs(point.y - creationDragStart.y)) > 8 else {
                return
            }
            let snappedPoint = Self.magnetizedLinePoint(from: creationDragStart, to: point)
            var line = ScreenshotEditorAnnotation.line(from: creationDragStart, to: snappedPoint, color: activeColor)
            line.strokeWidth = activeArrowStrokeWidth
            line.lineStyle = activeLineStyle
            document.performUndoableChange(actionName: "Add Line") {
                document.addAnnotation(line)
            }
        case .rectangle:
            let rect = CGRect(
                x: min(creationDragStart.x, point.x),
                y: min(creationDragStart.y, point.y),
                width: abs(point.x - creationDragStart.x),
                height: abs(point.y - creationDragStart.y)
            )
            guard rect.width > 6, rect.height > 6 else {
                return
            }
            switch activeRectangleMode {
            case .highlight:
                document.performUndoableChange(actionName: "Add Rectangle Highlight") {
                    var annotation = ScreenshotEditorAnnotation.highlight(rect, color: activeColor, fillOpacity: activeHighlightOpacity)
                    annotation.strokeWidth = activeArrowStrokeWidth
                    document.addAnnotation(annotation)
                }
            case .blur:
                document.performUndoableChange(actionName: "Add Blur") {
                    document.addAnnotation(.obscure(rect, style: .blur))
                }
            case .redact:
                document.performUndoableChange(actionName: "Add Redaction") {
                    document.addAnnotation(.obscure(rect, style: .redact))
                }
            }
        case .detail:
            guard hypot(point.x - creationDragStart.x, point.y - creationDragStart.y) > 12 else {
                return
            }
            let detail = ScreenshotEditorAnnotation.detail(
                sourcePoint: creationDragStart,
                bubbleCenter: point,
                color: activeColor,
                scale: activeDetailScale
            )
            document.performUndoableChange(actionName: "Add Detail Callout") {
                document.addAnnotation(detail)
            }
        case .hand, .crop, .text:
            break
        }

        document.endInteraction()
        notifyDocumentDidChange()
        activatePendingTextEditorIfNeeded()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoverState(for: boundedPoint(convert(event.locationInWindow, from: nil)))
        invalidateCursorState()
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        updateCursor(for: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        let point = boundedPoint(convert(event.locationInWindow, from: nil))
        onRequestMagnify?(point, event.magnification * 1.15)
    }

    override func scrollWheel(with event: NSEvent) {
        let isZoomGesture = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        guard isZoomGesture else {
            super.scrollWheel(with: event)
            return
        }

        let point = boundedPoint(convert(event.locationInWindow, from: nil))
        let dominantDelta = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        let zoomDelta = event.hasPreciseScrollingDeltas ? dominantDelta * -0.012 : dominantDelta * -0.03
        onRequestMagnify?(point, zoomDelta)
    }

    override func keyDown(with event: NSEvent) {
        if inlineTextEditorView != nil, event.keyCode == 53 {
            finishInlineTextEditing(commit: true)
            window?.makeFirstResponder(self)
            return
        }
        switch event.keyCode {
        case 53:
            cancelOperation(self)
        case 51, 117:
            deleteSelection()
        default:
            super.keyDown(with: event)
        }
    }

    @objc
    func deleteSelectionAction(_ sender: Any?) {
        deleteSelection()
    }

    @objc
    func undo(_ sender: Any?) {
        finishInlineTextEditing(commit: true)
        document.undo()
        notifyDocumentDidChange()
    }

    @objc
    func redo(_ sender: Any?) {
        finishInlineTextEditing(commit: true)
        document.redo()
        notifyDocumentDidChange()
    }

    override func cancelOperation(_ sender: Any?) {
        if inlineTextEditorView != nil {
            finishInlineTextEditing(commit: true)
            window?.makeFirstResponder(self)
            return
        }
        if document.selectedAnnotation != nil {
            document.selectAnnotation(id: nil)
            notifyDocumentDidChange()
            return
        }
        nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        drawCGImageInTopLeftCoordinates(document.image, in: bounds)

        for annotation in document.annotations {
            annotation.draw(baseImage: document.image)
            if annotation.id == document.selectedAnnotationID {
                annotation.drawSelection(
                    scale: interactionScale,
                    showsHandles: activeHandle != nil || hoveredAnnotationID == annotation.id
                )
                drawDeleteButton(for: annotation, scale: interactionScale, isHovered: isHoveringSelectedDeleteButton)
            }
        }

        if let cropRect = document.cropRect {
            let overlayPath = NSBezierPath(rect: bounds)
            let cropPath = NSBezierPath(rect: cropRect)
            overlayPath.append(cropPath)
            overlayPath.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.42).setFill()
            overlayPath.fill()

            NSColor.white.withAlphaComponent(0.95).setStroke()
            let dash: [CGFloat] = [8 / interactionScale, 6 / interactionScale]
            cropPath.setLineDash(dash, count: dash.count, phase: 0)
            cropPath.lineWidth = 2 / interactionScale
            cropPath.stroke()
            drawDeleteButton(
                in: cropDeleteButtonRect(for: cropRect, scale: interactionScale),
                scale: interactionScale,
                isHovered: isHoveringCropDeleteButton
            )

            if cropActiveHandle != nil || isHoveringCrop {
                for handleRect in cropHandleRects(for: cropRect).values {
                    drawHandle(in: handleRect, scale: interactionScale)
                }
            }
        }

        if let dragRect = currentCropDragRect {
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            dragRect.fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: dragRect)
            path.lineWidth = 2
            path.stroke()
        }

        if let previewAnnotation {
            previewAnnotation.draw(baseImage: document.image)
            previewAnnotation.drawSelection(scale: interactionScale, showsHandles: false)
        }
    }

    private var currentCropDragRect: CGRect? {
        guard let cropDragStart, let cropDragCurrent else { return nil }
        return CGRect(
            x: min(cropDragStart.x, cropDragCurrent.x),
            y: min(cropDragStart.y, cropDragCurrent.y),
            width: abs(cropDragCurrent.x - cropDragStart.x),
            height: abs(cropDragCurrent.y - cropDragStart.y)
        )
    }

    private var previewAnnotation: ScreenshotEditorAnnotation? {
        guard let creationDragStart, let creationDragCurrent else { return nil }
        switch tool {
        case .hand:
            return nil
        case .arrow:
            var arrow = ScreenshotEditorAnnotation.arrow(from: creationDragStart, to: creationDragCurrent, color: activeColor)
            arrow.strokeWidth = activeArrowStrokeWidth
            return arrow
        case .line:
            var line = ScreenshotEditorAnnotation.line(from: creationDragStart, to: Self.magnetizedLinePoint(from: creationDragStart, to: creationDragCurrent), color: activeColor)
            line.strokeWidth = activeArrowStrokeWidth
            line.lineStyle = activeLineStyle
            return line
        case .rectangle:
            let rect = CGRect(
                x: min(creationDragStart.x, creationDragCurrent.x),
                y: min(creationDragStart.y, creationDragCurrent.y),
                width: abs(creationDragCurrent.x - creationDragStart.x),
                height: abs(creationDragCurrent.y - creationDragStart.y)
            )
            switch activeRectangleMode {
            case .highlight:
                var annotation = ScreenshotEditorAnnotation.highlight(rect, color: activeColor, fillOpacity: activeHighlightOpacity)
                annotation.strokeWidth = activeArrowStrokeWidth
                return annotation
            case .blur:
                return .obscure(rect, style: .blur)
            case .redact:
                return .obscure(rect, style: .redact)
            }
        case .detail:
            return .detail(
                sourcePoint: creationDragStart,
                bubbleCenter: creationDragCurrent,
                color: activeColor,
                scale: activeDetailScale
            )
        case .crop, .text:
            return nil
        }
    }

    nonisolated static func magnetizedLinePoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
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

    private func boundedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }

    private func cropHandle(at point: CGPoint) -> ScreenshotAnnotationHandle? {
        guard let cropRect = document.cropRect else { return nil }
        return cropHandleRects(for: cropRect).first(where: { $0.value.contains(point) })?.key
    }

    func cropDeleteButtonRect(for rect: CGRect, scale: CGFloat) -> CGRect {
        let size: CGFloat = max(16 / scale, 18)
        let inset: CGFloat = max(6 / scale, 6)
        let normalized = rect.standardized
        return CGRect(
            x: normalized.maxX - size / 2,
            y: normalized.minY - size / 2 - inset,
            width: size,
            height: size
        )
    }

    private func cropHandleRects(for rect: CGRect) -> [ScreenshotAnnotationHandle: CGRect] {
        let handleSize: CGFloat = 12 / interactionScale
        let normalized = rect.standardized
        let midX = normalized.midX
        let midY = normalized.midY
        return [
            .topLeft: CGRect(x: normalized.minX - handleSize / 2, y: normalized.minY - handleSize / 2, width: handleSize, height: handleSize),
            .top: CGRect(x: midX - handleSize / 2, y: normalized.minY - handleSize / 2, width: handleSize, height: handleSize),
            .topRight: CGRect(x: normalized.maxX - handleSize / 2, y: normalized.minY - handleSize / 2, width: handleSize, height: handleSize),
            .right: CGRect(x: normalized.maxX - handleSize / 2, y: midY - handleSize / 2, width: handleSize, height: handleSize),
            .bottomLeft: CGRect(x: normalized.minX - handleSize / 2, y: normalized.maxY - handleSize / 2, width: handleSize, height: handleSize),
            .bottom: CGRect(x: midX - handleSize / 2, y: normalized.maxY - handleSize / 2, width: handleSize, height: handleSize),
            .bottomRight: CGRect(x: normalized.maxX - handleSize / 2, y: normalized.maxY - handleSize / 2, width: handleSize, height: handleSize),
            .left: CGRect(x: normalized.minX - handleSize / 2, y: midY - handleSize / 2, width: handleSize, height: handleSize)
        ]
    }

    private var interactionScale: CGFloat {
        max(enclosingScrollView?.magnification ?? 1, 0.0001)
    }

    private func drawHandle(in rect: CGRect, scale: CGFloat) {
        let handlePath = NSBezierPath(
            roundedRect: rect,
            xRadius: 3 / scale,
            yRadius: 3 / scale
        )
        NSColor.white.setFill()
        handlePath.fill()
        NSColor.controlAccentColor.setStroke()
        handlePath.lineWidth = 1 / scale
        handlePath.stroke()
    }

    private func invalidateCursorState() {
        window?.invalidateCursorRects(for: self)
        if let window {
            let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            updateHoverState(for: boundedPoint(location))
            updateCursor(for: location)
        }
    }

    private func updateHoverState(for point: CGPoint) {
        let nextHoveredAnnotationID: UUID?
        if let selected = document.selectedAnnotation, selected.contains(point) {
            nextHoveredAnnotationID = selected.id
        } else {
            nextHoveredAnnotationID = nil
        }
        let nextIsHoveringDeleteButton = document.selectedAnnotation?.deleteButtonRect(scale: interactionScale).contains(point) == true

        let nextIsHoveringCrop: Bool
        if tool == .crop {
            nextIsHoveringCrop = cropHandle(at: point) != nil || document.cropRect?.contains(point) == true
        } else {
            nextIsHoveringCrop = false
        }
        let nextIsHoveringCropDeleteButton = document.cropRect.map { cropDeleteButtonRect(for: $0, scale: interactionScale).contains(point) } == true

        guard hoveredAnnotationID != nextHoveredAnnotationID
                || isHoveringCrop != nextIsHoveringCrop
                || isHoveringSelectedDeleteButton != nextIsHoveringDeleteButton
                || isHoveringCropDeleteButton != nextIsHoveringCropDeleteButton else {
            return
        }

        hoveredAnnotationID = nextHoveredAnnotationID
        isHoveringCrop = nextIsHoveringCrop
        isHoveringSelectedDeleteButton = nextIsHoveringDeleteButton
        isHoveringCropDeleteButton = nextIsHoveringCropDeleteButton
        needsDisplay = true
    }

    private func updateCursor(for rawPoint: CGPoint) {
        if tool == .hand {
            if handPanLastPoint != nil {
                NSCursor.closedHand.set()
            } else {
                NSCursor.openHand.set()
            }
            return
        }

        guard tool == .crop else {
            let point = boundedPoint(rawPoint)
            if let activeHandle {
                cursor(for: activeHandle).set()
                return
            }
            if movingLastPoint != nil {
                NSCursor.closedHand.set()
                return
            }
            if let selected = document.selectedAnnotation {
                if selected.deleteButtonRect(scale: interactionScale).contains(point) {
                    NSCursor.pointingHand.set()
                    return
                }
                if let handle = selected.handle(at: point, scale: interactionScale) {
                    cursor(for: handle).set()
                    return
                }
                if selected.contains(point) {
                    NSCursor.openHand.set()
                    return
                }
            }
            NSCursor.arrow.set()
            return
        }

        let point = boundedPoint(rawPoint)
        if cropActiveHandle != nil {
            cursor(for: cropActiveHandle).set()
            return
        }
        if cropMoveLastPoint != nil {
            NSCursor.closedHand.set()
            return
        }
        if let cropRect = document.cropRect,
           cropDeleteButtonRect(for: cropRect, scale: interactionScale).contains(point) {
            NSCursor.pointingHand.set()
            return
        }
        if let handle = cropHandle(at: point) {
            cursor(for: handle).set()
            return
        }
        if let cropRect = document.cropRect, cropRect.contains(point) {
            NSCursor.openHand.set()
            return
        }
        NSCursor.crosshair.set()
    }

    private func panViewport(by delta: CGPoint) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let documentRect = clipView.documentRect
        let viewportSize = clipView.bounds.size
        let maxX = max(0, documentRect.width - viewportSize.width)
        let maxY = max(0, documentRect.height - viewportSize.height)

        let nextOrigin = CGPoint(
            x: min(max(clipView.bounds.origin.x - delta.x, 0), maxX),
            y: min(max(clipView.bounds.origin.y - delta.y, 0), maxY)
        )
        clipView.scroll(to: nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func cursor(for handle: ScreenshotAnnotationHandle?) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight:
            return .diagonalResizeUpLeftDownRight
        case .topRight, .bottomLeft:
            return .diagonalResizeUpRightDownLeft
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        case .arrowStart, .arrowEnd:
            return .crosshair
        default:
            return .crosshair
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView == inlineTextEditorView?.textView,
              let annotationID = inlineTextAnnotationID else { return }
        document.updateText(textView.string, for: annotationID)
        syncInlineTextEditorLayout()
    }

    func textDidEndEditing(_ notification: Notification) {
        finishInlineTextEditing(commit: true)
        window?.makeFirstResponder(self)
    }

    private func notifyDocumentDidChange() {
        onImageChanged?()
        onSelectionChanged?(document.selectedAnnotation)
        onCropChanged?(document.cropRect)
        needsDisplay = true
        invalidateCursorState()
    }

    private func drawDeleteButton(for annotation: ScreenshotEditorAnnotation, scale: CGFloat, isHovered: Bool) {
        drawDeleteButton(in: annotation.deleteButtonRect(scale: scale), scale: scale, isHovered: isHovered)
    }

    private func drawDeleteButton(in buttonRect: CGRect, scale: CGFloat, isHovered: Bool) {
        let path = NSBezierPath(ovalIn: buttonRect)
        let fillColor = isHovered
            ? NSColor.systemRed.withAlphaComponent(0.94)
            : NSColor.windowBackgroundColor.withAlphaComponent(0.82)
        fillColor.setFill()
        path.fill()
        let strokeColor = isHovered
            ? NSColor.systemRed
            : NSColor.systemRed.withAlphaComponent(0.35)
        strokeColor.setStroke()
        path.lineWidth = 1 / scale
        path.stroke()

        let inset = buttonRect.width * 0.28
        let crossPath = NSBezierPath()
        crossPath.move(to: CGPoint(x: buttonRect.minX + inset, y: buttonRect.minY + inset))
        crossPath.line(to: CGPoint(x: buttonRect.maxX - inset, y: buttonRect.maxY - inset))
        crossPath.move(to: CGPoint(x: buttonRect.maxX - inset, y: buttonRect.minY + inset))
        crossPath.line(to: CGPoint(x: buttonRect.minX + inset, y: buttonRect.maxY - inset))
        (isHovered ? NSColor.white : NSColor.systemRed).setStroke()
        crossPath.lineWidth = max(1.5 / scale, 1.5)
        crossPath.lineCapStyle = .round
        crossPath.stroke()
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0 && dy == 0 {
            return hypot(x - start.x, y - start.y)
        }

        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(x - projection.x, y - projection.y)
    }
}

private extension CGRect {
    var centerPoint: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension NSCursor {
    static let diagonalResizeUpLeftDownRight: NSCursor = makeDiagonalResizeCursor(
        symbolName: "arrow.up.left.and.down.right",
        fallback: .crosshair
    )

    static let diagonalResizeUpRightDownLeft: NSCursor = makeDiagonalResizeCursor(
        symbolName: "arrow.up.right.and.down.left",
        fallback: .crosshair
    )

    static func makeDiagonalResizeCursor(symbolName: String, fallback: NSCursor) -> NSCursor {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return fallback
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return NSCursor(image: image, hotSpot: CGPoint(x: image.size.width / 2, y: image.size.height / 2))
    }
}

private extension NSColor {
    func matches(_ other: NSColor) -> Bool {
        guard let lhs = usingColorSpace(.deviceRGB),
              let rhs = other.usingColorSpace(.deviceRGB) else {
            return isEqual(other)
        }
        return lhs.redComponent == rhs.redComponent &&
        lhs.greenComponent == rhs.greenComponent &&
        lhs.blueComponent == rhs.blueComponent &&
        lhs.alphaComponent == rhs.alphaComponent
    }
}
