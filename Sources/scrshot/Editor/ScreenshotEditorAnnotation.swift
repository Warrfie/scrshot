import AppKit
import CoreImage

func drawCGImageInTopLeftCoordinates(_ image: CGImage, in rect: CGRect) {
    guard let cgContext = NSGraphicsContext.current?.cgContext else {
        return
    }

    cgContext.saveGState()
    cgContext.translateBy(x: rect.minX, y: rect.maxY)
    cgContext.scaleBy(x: 1, y: -1)
    cgContext.draw(image, in: CGRect(origin: .zero, size: rect.size))
    cgContext.restoreGState()
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
    var detailSourceRect: CGRect
    var detailScale: CGFloat
    var detailShape: ScreenshotDetailShape

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
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
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
            fillOpacity: min(max(fillOpacity, 0), 1),
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: .zero,
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
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
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
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
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
        )
    }

    static func detail(sourcePoint: CGPoint, bubbleCenter: CGPoint, color: NSColor, lineWidth: CGFloat) -> ScreenshotEditorAnnotation {
        let size = CGSize(width: 140, height: 140)
        let origin = CGPoint(x: bubbleCenter.x - size.width / 2, y: bubbleCenter.y - size.height / 2)
        let sourceSize = CGSize(width: 70, height: 70)
        let sourceRect = CGRect(
            x: sourcePoint.x - sourceSize.width / 2,
            y: sourcePoint.y - sourceSize.height / 2,
            width: sourceSize.width,
            height: sourceSize.height
        )
        return ScreenshotEditorAnnotation(
            id: UUID(),
            kind: .detail,
            rect: CGRect(origin: origin, size: size),
            text: nil,
            color: color,
            strokeWidth: min(max(lineWidth, 0), 24),
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: 0,
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: sourcePoint,
            detailSourceRect: sourceRect,
            detailScale: 2,
            detailShape: .oval
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
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
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

    var effectiveDetailScale: CGFloat {
        let sourceRect = normalizedDetailSourceRect
        let bubbleRect = rect.standardized
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            return min(max(detailScale, 1.5), 6)
        }
        return min(max(min(bubbleRect.width / sourceRect.width, bubbleRect.height / sourceRect.height), 1.1), 8)
    }

    var normalizedDetailSourceRect: CGRect {
        if detailSourceRect.width > 0, detailSourceRect.height > 0 {
            let source = detailSourceRect.standardized
            let bubble = rect.standardized
            guard bubble.width > 0, bubble.height > 0 else { return source }
            return source.adjusted(toAspectRatio: bubble.width / bubble.height)
        }
        let bubbleRect = rect.standardized
        let scale = min(max(detailScale, 1.5), 6)
        let sampleWidth = max(bubbleRect.width / scale, 24)
        let sampleHeight = max(bubbleRect.height / scale, 24)
        return CGRect(
            x: detailSourcePoint.x - sampleWidth / 2,
            y: detailSourcePoint.y - sampleHeight / 2,
            width: sampleWidth,
            height: sampleHeight
        ).standardized
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
            let sourceRect = normalizedDetailSourceRect
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
            adjusted.detailSourceRect = adjusted.normalizedDetailSourceRect.offsetBy(dx: dx, dy: dy)
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

    func asHighlight(color: NSColor, fillOpacity: CGFloat, strokeWidth: CGFloat) -> ScreenshotEditorAnnotation {
        ScreenshotEditorAnnotation(
            id: id,
            kind: .highlight,
            rect: rect.standardized,
            text: nil,
            color: color,
            strokeWidth: min(max(strokeWidth, 0), 24),
            fontSize: 0,
            textAlignment: .left,
            obscureStyle: .redact,
            lineStyle: .solid,
            fillOpacity: min(max(fillOpacity, 0), 1),
            showsTextBackground: false,
            textBackgroundColor: .clear,
            detailSourcePoint: .zero,
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
        )
    }

    func asObscure(style: ScreenshotObscureStyle) -> ScreenshotEditorAnnotation {
        ScreenshotEditorAnnotation(
            id: id,
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
            detailSourceRect: .zero,
            detailScale: 2,
            detailShape: .oval
        )
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
        case .highlight, .obscure, .text:
            let bounds = rect.standardized
            return [
                .topLeft: CGRect(x: bounds.minX - handleSize / 2, y: bounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .topRight: CGRect(x: bounds.maxX - handleSize / 2, y: bounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .bottomLeft: CGRect(x: bounds.minX - handleSize / 2, y: bounds.maxY - handleSize / 2, width: handleSize, height: handleSize),
                .bottomRight: CGRect(x: bounds.maxX - handleSize / 2, y: bounds.maxY - handleSize / 2, width: handleSize, height: handleSize)
            ]
        case .detail:
            let bubbleBounds = rect.standardized
            let sourceBounds = normalizedDetailSourceRect
            return [
                .topLeft: CGRect(x: bubbleBounds.minX - handleSize / 2, y: bubbleBounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .topRight: CGRect(x: bubbleBounds.maxX - handleSize / 2, y: bubbleBounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .bottomLeft: CGRect(x: bubbleBounds.minX - handleSize / 2, y: bubbleBounds.maxY - handleSize / 2, width: handleSize, height: handleSize),
                .bottomRight: CGRect(x: bubbleBounds.maxX - handleSize / 2, y: bubbleBounds.maxY - handleSize / 2, width: handleSize, height: handleSize),
                .detailSourceTopLeft: CGRect(x: sourceBounds.minX - handleSize / 2, y: sourceBounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .detailSourceTopRight: CGRect(x: sourceBounds.maxX - handleSize / 2, y: sourceBounds.minY - handleSize / 2, width: handleSize, height: handleSize),
                .detailSourceBottomLeft: CGRect(x: sourceBounds.minX - handleSize / 2, y: sourceBounds.maxY - handleSize / 2, width: handleSize, height: handleSize),
                .detailSourceBottomRight: CGRect(x: sourceBounds.maxX - handleSize / 2, y: sourceBounds.maxY - handleSize / 2, width: handleSize, height: handleSize)
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
            let sourceRect = normalizedDetailSourceRect.insetBy(dx: -6, dy: -6)
            let lineDistance = point.distanceToSegment(start: connectorStartPoint, end: connectorEndPoint)
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
            let source = normalizedDetailSourceRect
            let union = current.union(source)
            let maxX = bounds.maxX - union.width
            let maxY = bounds.maxY - union.height
            let unionOrigin = CGPoint(
                x: min(max(union.minX + delta.x, bounds.minX), maxX),
                y: min(max(union.minY + delta.y, bounds.minY), maxY)
            )
            let clampedDelta = CGPoint(x: unionOrigin.x - union.minX, y: unionOrigin.y - union.minY)
            rect = current.offsetBy(dx: clampedDelta.x, dy: clampedDelta.y)
            detailSourceRect = source.offsetBy(dx: clampedDelta.x, dy: clampedDelta.y)
            detailSourcePoint = detailSourceRect.standardized.centerPoint
            detailScale = effectiveDetailScale
        }
    }

    mutating func moveDetailBubble(by delta: CGPoint, clampedTo bounds: CGRect) {
        guard kind == .detail else { return }
        let current = rect.standardized
        let maxX = bounds.maxX - current.width
        let maxY = bounds.maxY - current.height
        let origin = CGPoint(
            x: min(max(current.minX + delta.x, bounds.minX), maxX),
            y: min(max(current.minY + delta.y, bounds.minY), maxY)
        )
        rect = CGRect(origin: origin, size: current.size)
        detailScale = effectiveDetailScale
    }

    mutating func moveDetailSource(by delta: CGPoint, clampedTo bounds: CGRect) {
        guard kind == .detail else { return }
        let current = normalizedDetailSourceRect
        let maxX = bounds.maxX - current.width
        let maxY = bounds.maxY - current.height
        let origin = CGPoint(
            x: min(max(current.minX + delta.x, bounds.minX), maxX),
            y: min(max(current.minY + delta.y, bounds.minY), maxY)
        )
        detailSourceRect = CGRect(origin: origin, size: current.size)
        detailSourcePoint = detailSourceRect.standardized.centerPoint
        detailScale = effectiveDetailScale
    }

    mutating func resizeDetailSource(using handle: ScreenshotAnnotationHandle, to point: CGPoint, clampedTo bounds: CGRect) {
        guard kind == .detail else { return }
        detailSourceRect = resizedRect(
            normalizedDetailSourceRect,
            using: handle,
            to: point,
            clampedTo: bounds,
            minimumSide: 24
        )
        detailSourcePoint = detailSourceRect.standardized.centerPoint
        rect = rect.standardized.adjusted(toAspectRatio: detailSourceRect.standardized.aspectRatio)
        detailScale = effectiveDetailScale
    }

    private mutating func resizeDetailBubble(using handle: ScreenshotAnnotationHandle, to point: CGPoint, clampedTo bounds: CGRect) {
        let resized = resizedRect(
            rect.standardized,
            using: handle,
            to: point,
            clampedTo: bounds,
            minimumSide: 60
        )
        rect = resized
        detailSourceRect = normalizedDetailSourceRect.adjusted(toAspectRatio: rect.standardized.aspectRatio)
        detailSourcePoint = detailSourceRect.standardized.centerPoint
        detailScale = effectiveDetailScale
    }

    private func resizedRect(
        _ current: CGRect,
        using handle: ScreenshotAnnotationHandle,
        to point: CGPoint,
        clampedTo bounds: CGRect,
        minimumSide: CGFloat
    ) -> CGRect {
        let clampedPoint = point.clamped(to: bounds)
        var minX = current.minX
        var minY = current.minY
        var maxX = current.maxX
        var maxY = current.maxY

        switch handle {
        case .topLeft, .detailSourceTopLeft:
            minX = clampedPoint.x
            minY = clampedPoint.y
        case .topRight, .detailSourceTopRight:
            maxX = clampedPoint.x
            minY = clampedPoint.y
        case .bottomLeft, .detailSourceBottomLeft:
            minX = clampedPoint.x
            maxY = clampedPoint.y
        case .bottomRight, .detailSourceBottomRight:
            maxX = clampedPoint.x
            maxY = clampedPoint.y
        default:
            break
        }

        let width = max(minimumSide, abs(maxX - minX))
        let height = max(minimumSide, abs(maxY - minY))
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: width, height: height)
            .intersection(bounds)
    }

    var connectorStartPoint: CGPoint {
        let source = normalizedDetailSourceRect
        let bubble = rect.standardized
        return detailEdgePoint(in: source, toward: bubble.centerPoint)
    }

    var connectorEndPoint: CGPoint {
        let source = normalizedDetailSourceRect
        let bubble = rect.standardized
        return detailEdgePoint(in: bubble, toward: source.centerPoint)
    }

    private func detailEdgePoint(in rect: CGRect, toward target: CGPoint) -> CGPoint {
        switch detailShape {
        case .oval:
            return rect.ellipseEdgePoint(toward: target)
        case .rectangle:
            return rect.edgePoint(toward: target)
        }
    }

    private func detailPath(in rect: CGRect) -> NSBezierPath {
        switch detailShape {
        case .oval:
            return NSBezierPath(ovalIn: rect)
        case .rectangle:
            return NSBezierPath(rect: rect)
        }
    }

    func detailRegion(at point: CGPoint) -> ScreenshotDetailRegion? {
        guard kind == .detail else { return nil }
        if rect.standardized.insetBy(dx: -6, dy: -6).contains(point) {
            return .bubble
        }
        if normalizedDetailSourceRect.insetBy(dx: -6, dy: -6).contains(point) {
            return .source
        }
        if point.distanceToSegment(start: connectorStartPoint, end: connectorEndPoint) <= 8 {
            return .all
        }
        return nil
    }

    mutating func resizeDetail(using handle: ScreenshotAnnotationHandle, to point: CGPoint, clampedTo bounds: CGRect) {
        switch handle {
        case .detailSourceTopLeft, .detailSourceTopRight, .detailSourceBottomLeft, .detailSourceBottomRight:
            resizeDetailSource(using: handle, to: point, clampedTo: bounds)
        default:
            resizeDetailBubble(using: handle, to: point, clampedTo: bounds)
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
                let snappedPoint = magnetizedLinePoint(from: endPoint, to: clampedPoint)
                rect = CGRect(x: snappedPoint.x, y: snappedPoint.y, width: endPoint.x - snappedPoint.x, height: endPoint.y - snappedPoint.y)
            case .arrowEnd:
                let snappedPoint = magnetizedLinePoint(from: startPoint, to: clampedPoint)
                rect = CGRect(x: startPoint.x, y: startPoint.y, width: snappedPoint.x - startPoint.x, height: snappedPoint.y - startPoint.y)
            default:
                break
            }
        case .highlight, .obscure, .text:
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
        case .detail:
            resizeDetail(using: handle, to: point, clampedTo: bounds)
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
        case .highlight, .obscure, .text:
            return NSBezierPath(rect: selectionBounds)
        case .detail:
            let path = detailPath(in: normalizedDetailSourceRect)
            path.append(detailPath(in: rect.standardized))
            return path
        }
    }

    private func drawRectangle(baseImage: CGImage?) {
        let boxRect = rect.standardized.integral
        guard boxRect.width > 0, boxRect.height > 0 else { return }

        switch kind {
        case .highlight:
            let path = NSBezierPath(rect: boxRect)
            if fillOpacity > 0 {
                color.withAlphaComponent(color.alphaComponent * fillOpacity).setFill()
                path.fill()
            }
            if strokeWidth > 0 {
                color.setStroke()
                path.lineWidth = strokeWidth
                path.stroke()
            }
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
        let bubbleRect = rect.standardized
        guard bubbleRect.width > 20, bubbleRect.height > 20 else { return }

        let sourceRect = normalizedDetailSourceRect
        let sampleRect = sourceRect.integral
            .intersection(CGRect(origin: .zero, size: CGSize(width: baseImage.width, height: baseImage.height)))

        if strokeWidth > 0 {
            let connector = NSBezierPath()
            connector.move(to: connectorStartPoint)
            connector.line(to: connectorEndPoint)
            color.withAlphaComponent(0.9).setStroke()
            connector.lineWidth = strokeWidth
            connector.lineCapStyle = .round
            connector.stroke()

            let sourceMarker = detailPath(in: sourceRect)
            color.setStroke()
            sourceMarker.lineWidth = strokeWidth
            sourceMarker.stroke()
        }

        guard let zoomedImage = Self.croppedImage(from: baseImage, in: sampleRect) else { return }

        let clipPath = detailPath(in: bubbleRect)
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        drawCGImageInTopLeftCoordinates(zoomedImage, in: bubbleRect)
        NSGraphicsContext.restoreGraphicsState()

        if strokeWidth > 0 {
            let bubblePath = detailPath(in: bubbleRect)
            color.setStroke()
            bubblePath.lineWidth = strokeWidth
            bubblePath.stroke()
        }
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
        lhs.detailSourceRect == rhs.detailSourceRect &&
        lhs.detailScale == rhs.detailScale &&
        lhs.detailShape == rhs.detailShape &&
        lhs.color.matches(rhs.color) &&
        lhs.textBackgroundColor.matches(rhs.textBackgroundColor)
    }
}
