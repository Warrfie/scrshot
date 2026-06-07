import AppKit

@MainActor
final class ScreenshotEditorCanvasView: NSView, NSTextViewDelegate {
    var tool: ScreenshotEditorTool = .arrow
    var activeColor: NSColor = .systemRed
    var activeArrowStrokeWidth: CGFloat = 8
    var activeRectangleMode: ScreenshotRectangleToolMode = .blur
    var activeLineStyle: ScreenshotLineStyle = .solid
    var activeDetailShape: ScreenshotDetailShape = .oval
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
    private var movingDetailRegion: ScreenshotDetailRegion?
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
        let allowsZero = document.selectedAnnotation?.kind == .detail
            || document.selectedAnnotation?.kind == .highlight
            || (document.selectedAnnotation == nil && (tool == .rectangle || tool == .detail))
        activeArrowStrokeWidth = min(max(strokeWidth, allowsZero ? 0 : 2), 24)
        if document.selectedAnnotation?.kind == .arrow
            || document.selectedAnnotation?.kind == .line
            || document.selectedAnnotation?.kind == .highlight
            || document.selectedAnnotation?.kind == .detail {
            document.performUndoableChange(actionName: "Change Stroke Width") {
                document.updateSelectedStrokeWidth(activeArrowStrokeWidth)
            }
            notifyDocumentDidChange()
        }
    }

    func applyDetailShape(_ shape: ScreenshotDetailShape) {
        activeDetailShape = shape
        if document.selectedAnnotation?.kind == .detail {
            document.performUndoableChange(actionName: "Change Detail Shape") {
                document.updateSelectedDetailShape(shape)
            }
            notifyDocumentDidChange()
        }
    }

    func applyTextFontSize(_ fontSize: CGFloat) {
        activeTextFontSize = min(max(fontSize, 12), 192)
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
        if document.selectedAnnotation?.kind == .highlight || document.selectedAnnotation?.kind == .obscure {
            document.performUndoableChange(actionName: "Change Rectangle Mode") {
                document.updateSelectedRectangleMode(
                    mode,
                    defaultColor: activeColor,
                    defaultStrokeWidth: activeArrowStrokeWidth
                )
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

    func clearSelectionForToolChange() {
        finishInlineTextEditing(commit: true)
        guard document.selectedAnnotationID != nil else { return }
        document.selectAnnotation(id: nil)
        onSelectionChanged?(nil)
        needsDisplay = true
        invalidateCursorState()
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
            movingDetailRegion = hitAnnotation.kind == .detail ? hitAnnotation.detailRegion(at: point) : nil
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
            if document.selectedAnnotation?.kind == .detail, let movingDetailRegion {
                document.moveSelectedDetailRegion(movingDetailRegion, by: delta)
            } else {
                document.moveSelected(by: delta)
            }
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
            movingDetailRegion = nil
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
            arrow.strokeWidth = max(activeArrowStrokeWidth, 2)
            document.performUndoableChange(actionName: "Add Arrow") {
                document.addAnnotation(arrow)
            }
        case .line:
            guard max(abs(point.x - creationDragStart.x), abs(point.y - creationDragStart.y)) > 8 else {
                return
            }
            let snappedPoint = magnetizedLinePoint(from: creationDragStart, to: point)
            var line = ScreenshotEditorAnnotation.line(from: creationDragStart, to: snappedPoint, color: activeColor)
            line.strokeWidth = max(activeArrowStrokeWidth, 2)
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
                document.performUndoableChange(actionName: "Add Filled Rectangle") {
                    var annotation = ScreenshotEditorAnnotation.highlight(rect, color: activeColor, fillOpacity: 1)
                    annotation.strokeWidth = 0
                    document.addAnnotation(annotation)
                }
            case .blur:
                document.performUndoableChange(actionName: "Add Blur") {
                    document.addAnnotation(.obscure(rect, style: .blur))
                }
            case .outline:
                document.performUndoableChange(actionName: "Add Outline Rectangle") {
                    var annotation = ScreenshotEditorAnnotation.highlight(rect, color: activeColor, fillOpacity: 0)
                    annotation.strokeWidth = activeArrowStrokeWidth
                    document.addAnnotation(annotation)
                }
            }
        case .detail:
            guard hypot(point.x - creationDragStart.x, point.y - creationDragStart.y) > 12 else {
                return
            }
            var detail = ScreenshotEditorAnnotation.detail(
                sourcePoint: creationDragStart,
                bubbleCenter: point,
                color: activeColor,
                lineWidth: activeArrowStrokeWidth
            )
            detail.detailShape = activeDetailShape
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
            arrow.strokeWidth = max(activeArrowStrokeWidth, 2)
            return arrow
        case .line:
            var line = ScreenshotEditorAnnotation.line(from: creationDragStart, to: magnetizedLinePoint(from: creationDragStart, to: creationDragCurrent), color: activeColor)
            line.strokeWidth = max(activeArrowStrokeWidth, 2)
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
                var annotation = ScreenshotEditorAnnotation.highlight(rect, color: activeColor, fillOpacity: 1)
                annotation.strokeWidth = 0
                return annotation
            case .blur:
                return .obscure(rect, style: .blur)
            case .outline:
                var annotation = ScreenshotEditorAnnotation.highlight(rect, color: activeColor, fillOpacity: 0)
                annotation.strokeWidth = activeArrowStrokeWidth
                return annotation
            }
        case .detail:
            var detail = ScreenshotEditorAnnotation.detail(
                sourcePoint: creationDragStart,
                bubbleCenter: creationDragCurrent,
                color: activeColor,
                lineWidth: activeArrowStrokeWidth
            )
            detail.detailShape = activeDetailShape
            return detail
        case .crop, .text:
            return nil
        }
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
