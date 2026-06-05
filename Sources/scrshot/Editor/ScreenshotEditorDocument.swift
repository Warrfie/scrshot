import AppKit

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
        if annotations[index].kind == .highlight, strokeWidth <= 0 {
            annotations[index].strokeWidth = 0
        } else {
            annotations[index].strokeWidth = min(max(strokeWidth, 2), 24)
        }
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
        annotations[index].fillOpacity = min(max(opacity, 0), 1)
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
