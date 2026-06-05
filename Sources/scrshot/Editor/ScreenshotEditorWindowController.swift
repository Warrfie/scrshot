import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    var onComplete: ((CGImage?) -> Void)?

    private let editorViewController: ScreenshotEditorViewController
    private let editorShellViewModel: ScreenshotEditorShellViewModel
    private let hostingController: NSHostingController<ScreenshotEditorShellView>
    private let initialWindowSize: NSSize
    private let preferredDisplayID: CGDirectDisplayID?
    private let screenPlacement: ScreenshotEditorScreenPlacement

    init(image: CGImage, preferredDisplayID: CGDirectDisplayID?) {
        self.preferredDisplayID = preferredDisplayID
        self.screenPlacement = ScreenshotEditorScreenPlacement(preferredDisplayID: preferredDisplayID)
        self.editorViewController = ScreenshotEditorViewController(image: image, preferredDisplayID: preferredDisplayID)
        self.editorShellViewModel = ScreenshotEditorShellViewModel()
        self.hostingController = TitlebarlessHostingController(
            rootView: ScreenshotEditorShellView(viewModel: editorShellViewModel, editorViewController: editorViewController)
        )
        self.initialWindowSize = editorViewController.initialWindowSize

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 700, height: 360)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        super.init(window: window)

        window.delegate = self
        editorViewController.bindShellViewModel(editorShellViewModel)
        editorShellViewModel.bind(to: editorViewController)
        editorShellViewModel.onCancel = { [weak self] in
            self?.finish(with: nil)
        }
        editorShellViewModel.onDone = { [weak self] image in
            self?.finish(with: image)
        }
        editorShellViewModel.onCloseWindow = { [weak window] in
            window?.performClose(nil)
        }
        editorShellViewModel.onMinimizeWindow = { [weak window] in
            window?.miniaturize(nil)
        }
        editorShellViewModel.onZoomWindow = { [weak window] in
            window?.zoom(nil)
        }
        editorViewController.onCancel = { [weak self] in
            self?.finish(with: nil)
        }
        editorViewController.onDone = { [weak self] image in
            self?.finish(with: image)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        AppLogger.shared.debug(.editorWindow, "show begin frame=\(NSStringFromRect(window.frame))")
        let targetFrame = screenPlacement.frameCenteredOnPreferredScreen(size: initialWindowSize)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
        showWindow(nil)
        window.setFrame(targetFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            AppLogger.shared.debug(.editorWindow, "show async before center frame=\(NSStringFromRect(window.frame))")
            window.setFrame(self.screenPlacement.frameCenteredOnPreferredScreen(size: self.initialWindowSize), display: true)
            self.screenPlacement.center(window)
            AppLogger.shared.debug(.editorWindow, "show async after center frame=\(NSStringFromRect(window.frame))")
            window.displayIfNeeded()
            window.orderFrontRegardless()
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                AppLogger.shared.debug(.editorWindow, "show async recenter before frame=\(NSStringFromRect(window.frame))")
                self.screenPlacement.center(window)
                AppLogger.shared.debug(.editorWindow, "show async recenter after frame=\(NSStringFromRect(window.frame))")
                window.displayIfNeeded()
                window.orderFrontRegardless()
                self.editorViewController.fitContentToWindowIfNeeded()
            }
        }
    }

    func presentVisibilityAlert() {
        AppMessageWindowController.present(
            title: "Editor should be open",
            message: "If you do not see the editor window, use Mission Control or hide other windows.",
            details: "scrshot is trying to bring the editor back to the front.",
            secondaryButtonTitle: "OK"
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard onComplete != nil else { return }
        let completion = onComplete
        onComplete = nil
        completion?(nil)
    }

    private func finish(with image: CGImage?) {
        let completion = onComplete
        onComplete = nil
        window?.close()
        completion?(image)
    }

}

@MainActor
final class ScreenshotEditorViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onDone: ((CGImage) -> Void)?
    private weak var shellViewModel: ScreenshotEditorShellViewModel?

    private let document: ScreenshotEditorDocument
    private let documentContainerView = FlippedDocumentContainerView()
    private lazy var canvasView = ScreenshotEditorCanvasView(document: document)
    private let scrollView = NSScrollView()
    private var hasAppliedInitialFit = false
    private let preferredDisplayID: CGDirectDisplayID?
    private let screenPlacement: ScreenshotEditorScreenPlacement
    private var canvasMargins = CGSize(width: 2, height: 0)
    private let editorShellHorizontalPadding: CGFloat = 15
    private let editorShellBottomPadding: CGFloat = 10
    private let editorShellTopPadding: CGFloat = 15
    private let editorToolbarCanvasSpacing: CGFloat = 10
    private var lastViewportSize: CGSize?
    override var undoManager: UndoManager? { canvasView.undoManager }

    init(image: CGImage, preferredDisplayID: CGDirectDisplayID?) {
        self.document = ScreenshotEditorDocument(image: image)
        self.preferredDisplayID = preferredDisplayID
        self.screenPlacement = ScreenshotEditorScreenPlacement(preferredDisplayID: preferredDisplayID)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var initialWindowSize: NSSize {
        let visibleFrame = screenPlacement.visibleFrame
        let targetWidth = min(max(visibleFrame.width * 0.58, 920), visibleFrame.width - 80)
        let canvasAspectRatio = document.canvasSize.height / max(document.canvasSize.width, 1)
        let estimatedToolbarHeight: CGFloat = 40
        let targetCanvasWidth = max(targetWidth - editorShellHorizontalPadding * 2, 1)
        let fittedContentHeight = targetCanvasWidth * canvasAspectRatio
        let targetHeight = min(
            max(
                fittedContentHeight +
                estimatedToolbarHeight +
                editorToolbarCanvasSpacing +
                editorShellTopPadding +
                editorShellBottomPadding,
                360
            ),
            visibleFrame.height - 80
        )
        return NSSize(width: targetWidth, height: targetHeight)
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 4
        documentContainerView.frame = CGRect(origin: .zero, size: document.canvasSize)
        canvasView.frame = CGRect(origin: .zero, size: document.canvasSize)
        documentContainerView.addSubview(canvasView)
        scrollView.documentView = documentContainerView
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        view = root
        refreshDocumentContainer(visibleSize: document.canvasSize)
        configureCanvas()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        AppLogger.shared.debug(.editorWindow, "viewDidAppear viewport=\(describe(size: viewportSize)) frame=\(NSStringFromRect(view.window?.frame ?? .zero))")
        applyInitialFitIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        AppLogger.shared.debug(.editorWindow, "viewDidLayout viewport=\(describe(size: viewportSize)) frame=\(NSStringFromRect(view.window?.frame ?? .zero))")
        refreshDocumentContainer(visibleSize: currentVisibleSize)
        refitCanvasAfterViewportResizeIfNeeded()
        applyInitialFitIfNeeded()
    }

    func fitContentToWindowIfNeeded() {
        applyInitialFitIfNeeded(force: true)
    }

    func fitContentToWindow() {
        hasAppliedInitialFit = true
        fitCanvasToViewport(animated: false)
    }

    func fitContent(to rect: CGRect) {
        hasAppliedInitialFit = true
        fit(rect: rect, animated: true)
    }

    fileprivate func bindShellViewModel(_ shellViewModel: ScreenshotEditorShellViewModel) {
        self.shellViewModel = shellViewModel
    }

    func selectTool(_ tool: ScreenshotEditorTool) {
        canvasView.tool = tool
        canvasView.clearSelectionForToolChange()
        updateInspector(for: nil)
        view.window?.makeFirstResponder(canvasView)
    }

    func setAnnotationColor(_ color: NSColor) {
        canvasView.applyColor(color)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setRectangleColor(_ color: NSColor) {
        canvasView.applyColor(color)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setArrowStrokeWidth(_ width: CGFloat) {
        canvasView.applyArrowStrokeWidth(width)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setRectangleMode(_ mode: ScreenshotRectangleToolMode) {
        canvasView.applyRectangleMode(mode)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setRectangleStrokeEnabled(_ enabled: Bool) {
        canvasView.applyRectangleStrokeEnabled(enabled)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setDetailScale(_ scale: CGFloat) {
        canvasView.applyDetailScale(scale)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setLineStyle(_ style: ScreenshotLineStyle) {
        canvasView.applyLineStyle(style)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setTextSize(_ size: CGFloat) {
        canvasView.applyTextFontSize(size)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func setTextAlignment(_ alignment: NSTextAlignment) {
        canvasView.applyTextAlignment(alignment)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    func renderedImage() -> CGImage? {
        canvasView.makeRenderedImage()
    }

    private func configureCanvas() {
        canvasView.tool = .hand
        canvasView.activeColor = .systemRed
        canvasView.activeArrowStrokeWidth = 8
        canvasView.activeRectangleMode = .blur
        canvasView.activeLineStyle = .solid
        canvasView.activeDetailScale = 2
        canvasView.activeTextFontSize = 28
        canvasView.activeTextShowsBackground = false
        canvasView.activeTextBackgroundColor = NSColor.black.withAlphaComponent(0.55)
        canvasView.activeTextAlignment = .left
        canvasView.onImageChanged = { [weak self] in
            self?.canvasView.needsDisplay = true
        }
        canvasView.onRequestFitToWindow = { [weak self] in
            self?.fitContentToWindow()
        }
        canvasView.onRequestFitToRect = { [weak self] rect in
            self?.fitContent(to: rect)
        }
        canvasView.onRequestMagnify = { [weak self] _, delta in
            self?.adjustMagnification(by: delta)
        }
        canvasView.onSelectionChanged = { [weak self] annotation in
            self?.updateInspector(for: annotation)
        }
        updateInspector(for: nil)
    }

    @objc
    private func fitTapped() {
        if let cropRect = canvasView.cropRect {
            logFit("fit button pressed with cropRect=\(describe(rect: cropRect))")
            fitContent(to: cropRect)
        } else {
            logFit("fit button pressed for full image")
            fitContentToWindow()
        }
    }

    @objc
    func fitToWindowAction(_ sender: Any?) {
        fitTapped()
    }

    @objc
    func zoomInAction(_ sender: Any?) {
        adjustMagnification(by: 0.2)
    }

    @objc
    func zoomOutAction(_ sender: Any?) {
        adjustMagnification(by: -0.1667)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    private func applyInitialFitIfNeeded(force: Bool = false) {
        guard force || !hasAppliedInitialFit else { return }
        let viewportSize = viewportSize
        guard viewportSize.width > 1, viewportSize.height > 1 else {
            return
        }
        hasAppliedInitialFit = true
        fitCanvasToViewport(animated: false)
        lastViewportSize = viewportSize
    }

    private func refitCanvasAfterViewportResizeIfNeeded() {
        guard hasAppliedInitialFit else {
            lastViewportSize = viewportSize
            return
        }

        let currentViewportSize = viewportSize
        guard currentViewportSize.width > 1, currentViewportSize.height > 1 else { return }

        guard let previousViewportSize = lastViewportSize else {
            lastViewportSize = currentViewportSize
            return
        }

        let didResize =
            abs(currentViewportSize.width - previousViewportSize.width) > 0.5 ||
            abs(currentViewportSize.height - previousViewportSize.height) > 0.5

        guard didResize else { return }

        lastViewportSize = currentViewportSize
        logFit(
            "viewport resized previous=\(describe(size: previousViewportSize)) current=\(describe(size: currentViewportSize)); refit canvas"
        )
        fitCanvasToViewport(animated: false)
    }

    private func fitCanvasToViewport(animated: Bool) {
        updateMinimumMagnification()
        logFit("fitCanvasToViewport focusRect=\(describe(rect: document.focusRect)) viewport=\(describe(size: viewportSize)) minMagnification=\(format(scrollView.minMagnification))")
        fit(rect: document.focusRect, animated: animated)
    }

    private func fit(rect: CGRect, animated: Bool) {
        let viewportSize = viewportSize
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let targetRect = targetRectForFit(from: rect, viewportSize: viewportSize)
        let idealMagnification = targetMagnificationForFit(from: rect, viewportSize: viewportSize)
        let targetMagnification = min(
            scrollView.maxMagnification,
            max(scrollView.minMagnification, idealMagnification)
        )
        let visibleSize = CGSize(
            width: viewportSize.width / targetMagnification,
            height: viewportSize.height / targetMagnification
        )
        refreshDocumentContainer(visibleSize: visibleSize)
        let centerPoint = containerPoint(fromCanvas: CGPoint(x: rect.midX, y: rect.midY))

        logFit(
            "fit rect=\(describe(rect: rect)) targetRect=\(describe(rect: targetRect)) " +
            "viewport=\(describe(size: viewportSize)) idealMagnification=\(format(idealMagnification)) " +
            "targetMagnification=\(format(targetMagnification)) center=\(describe(point: centerPoint)) animated=\(animated)"
        )

        applyFit(magnification: targetMagnification, centeredAt: centerPoint, targetRect: targetRect, animated: animated)
    }

    private func applyFit(magnification: CGFloat, centeredAt centerPoint: CGPoint, targetRect: CGRect, animated: Bool) {
        logFit("applyFit magnification=\(format(magnification)) center=\(describe(point: centerPoint)) animatedRequest=\(animated)")
        scrollView.setMagnification(magnification, centeredAt: centerPoint)
        centerViewport(around: targetRect, magnification: magnification)
    }

    private func applyMagnification(_ magnification: CGFloat, centeredAt centerPoint: CGPoint, animated: Bool) {
        logFit("applyMagnification magnification=\(format(magnification)) center=\(describe(point: centerPoint)) animated=\(animated)")
        let targetVisibleSize = CGSize(
            width: viewportSize.width / magnification,
            height: viewportSize.height / magnification
        )
        let canvasCenter = visibleCanvasCenter
        refreshDocumentContainer(visibleSize: targetVisibleSize)
        let adjustedCenterPoint = containerPoint(fromCanvas: canvasCenter)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                scrollView.animator().setMagnification(magnification, centeredAt: adjustedCenterPoint)
            }
        } else {
            scrollView.setMagnification(magnification, centeredAt: adjustedCenterPoint)
        }
    }

    private func targetRectForFit(from rect: CGRect, viewportSize: CGSize) -> CGRect {
        let normalized = rect.standardized
        let fullRect = CGRect(origin: .zero, size: document.canvasSize)
        guard normalized.width < fullRect.width || normalized.height < fullRect.height else {
            return fullRect
        }

        let basePadding: CGFloat = 0
        let paddedRect = normalized.insetBy(dx: -basePadding, dy: -basePadding)
        let magnification = targetMagnificationForFit(from: paddedRect, viewportSize: viewportSize)
        let visibleSize = CGSize(
            width: viewportSize.width / magnification,
            height: viewportSize.height / magnification
        )

        let centeredRect = CGRect(
            x: paddedRect.midX - visibleSize.width / 2,
            y: paddedRect.midY - visibleSize.height / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )

        return clampedRect(centeredRect, inside: fullRect)
    }

    private func targetMagnificationForFit(from rect: CGRect, viewportSize: CGSize) -> CGFloat {
        let normalized = rect.standardized
        let widthScale = viewportSize.width / normalized.width
        let heightScale = viewportSize.height / normalized.height
        return min(widthScale, heightScale)
    }

    private func centerViewport(around rect: CGRect, magnification: CGFloat) {
        let clipView = scrollView.contentView
        let visibleSize = CGSize(
            width: scrollView.contentSize.width / magnification,
            height: scrollView.contentSize.height / magnification
        )
        guard visibleSize.width > 0, visibleSize.height > 0 else { return }

        let documentRect = CGRect(origin: .zero, size: documentContainerView.frame.size)
        let adjustedRect = CGRect(
            x: rect.origin.x + canvasMargins.width,
            y: rect.origin.y + canvasMargins.height,
            width: rect.width,
            height: rect.height
        )
        let proposedOrigin = CGPoint(
            x: adjustedRect.midX - visibleSize.width / 2,
            y: adjustedRect.midY - visibleSize.height / 2
        )
        let clampedOrigin = CGPoint(
            x: min(max(proposedOrigin.x, documentRect.minX), max(documentRect.maxX - visibleSize.width, documentRect.minX)),
            y: min(max(proposedOrigin.y, documentRect.minY), max(documentRect.maxY - visibleSize.height, documentRect.minY))
        )

        logFit(
            "centerViewport rect=\(describe(rect: rect)) adjustedRect=\(describe(rect: adjustedRect)) visibleSize=\(describe(size: visibleSize)) " +
            "proposedOrigin=\(describe(point: proposedOrigin)) clampedOrigin=\(describe(point: clampedOrigin)) " +
            "documentRect=\(describe(rect: documentRect))"
        )
        clipView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(clipView)
        logFit("centerViewport result clipBounds=\(describe(rect: clipView.bounds)) magnification=\(format(scrollView.magnification))")
    }

    private func adjustMagnification(by delta: CGFloat) {
        updateMinimumMagnification()
        let current = scrollView.magnification
        let target = min(scrollView.maxMagnification, max(scrollView.minMagnification, current * (1 + delta)))
        guard abs(target - current) > 0.0001 else { return }
        hasAppliedInitialFit = true
        applyMagnification(target, centeredAt: visibleContentCenter, animated: false)
    }

    private var visibleContentCenter: CGPoint {
        let clipView = scrollView.contentView
        return CGPoint(
            x: clipView.bounds.midX,
            y: clipView.bounds.midY
        )
    }

    private var visibleCanvasCenter: CGPoint {
        clampedPoint(
            canvasPoint(fromContainer: visibleContentCenter),
            to: CGRect(origin: .zero, size: document.canvasSize)
        )
    }

    private func clampedRect(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        var clamped = rect

        if clamped.width > bounds.width {
            clamped.size.width = bounds.width
            clamped.origin.x = bounds.minX
        } else {
            clamped.origin.x = min(max(clamped.origin.x, bounds.minX), bounds.maxX - clamped.width)
        }

        if clamped.height > bounds.height {
            clamped.size.height = bounds.height
            clamped.origin.y = bounds.minY
        } else {
            clamped.origin.y = min(max(clamped.origin.y, bounds.minY), bounds.maxY - clamped.height)
        }

        return clamped
    }

    private func updateMinimumMagnification() {
        let viewportSize = viewportSize
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let widthScale = viewportSize.width / document.canvasSize.width
        let heightScale = viewportSize.height / document.canvasSize.height
        scrollView.minMagnification = min(1, min(widthScale, heightScale))
    }

    private var viewportSize: CGSize {
        scrollView.contentSize
    }

    private var currentVisibleSize: CGSize {
        let magnification = max(scrollView.magnification, 0.0001)
        return CGSize(
            width: viewportSize.width / magnification,
            height: viewportSize.height / magnification
        )
    }

    private func refreshDocumentContainer(visibleSize: CGSize) {
        let minimumMargin: CGFloat = 2
        let horizontalMargin = max((visibleSize.width - document.canvasSize.width) / 2, minimumMargin)
        let verticalMargin = max((visibleSize.height - document.canvasSize.height) / 2, minimumMargin)
        canvasMargins = CGSize(width: horizontalMargin, height: verticalMargin)

        let containerSize = CGSize(
            width: document.canvasSize.width + horizontalMargin * 2,
            height: document.canvasSize.height + verticalMargin * 2
        )
        documentContainerView.frame = CGRect(origin: .zero, size: containerSize)
        canvasView.frame = CGRect(origin: CGPoint(x: horizontalMargin, y: verticalMargin), size: document.canvasSize)
    }

    private func containerPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + canvasMargins.width, y: point.y + canvasMargins.height)
    }

    private func canvasPoint(fromContainer point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - canvasMargins.width, y: point.y - canvasMargins.height)
    }

    private func clampedPoint(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func logFit(_ message: String) {
        AppLogger.shared.debug(.editorFit, message)
    }

    private func describe(rect: CGRect) -> String {
        "{x=\(format(rect.origin.x)), y=\(format(rect.origin.y)), w=\(format(rect.size.width)), h=\(format(rect.size.height))}"
    }

    private func describe(size: CGSize) -> String {
        "{w=\(format(size.width)), h=\(format(size.height))}"
    }

    private func describe(point: CGPoint) -> String {
        "{x=\(format(point.x)), y=\(format(point.y))}"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private func updateInspector(for annotation: ScreenshotEditorAnnotation?) {
        let inspectorColor = (annotation?.kind != .obscure ? annotation?.color : nil) ?? canvasView.activeColor

        let arrowWidth = annotation?.kind == .arrow || annotation?.kind == .line || annotation?.kind == .highlight
            ? (annotation?.strokeWidth ?? 6)
            : canvasView.activeArrowStrokeWidth

        let lineStyle = annotation?.kind == .line ? (annotation?.lineStyle ?? .solid) : canvasView.activeLineStyle

        let rectangleMode: ScreenshotRectangleToolMode
        if annotation?.kind == .highlight {
            rectangleMode = (annotation?.fillOpacity ?? 1) > 0 ? .highlight : .outline
        } else if annotation?.kind == .obscure {
            rectangleMode = annotation?.obscureStyle == .blur ? .blur : .outline
        } else {
            rectangleMode = canvasView.activeRectangleMode
        }

        let rectangleStrokeEnabled = annotation?.kind == .highlight
            ? (annotation?.strokeWidth ?? 0) > 0
            : canvasView.activeRectangleStrokeEnabled
        let detailScale = annotation?.kind == .detail
            ? (annotation?.detailScale ?? canvasView.activeDetailScale)
            : canvasView.activeDetailScale

        let textSize: CGFloat
        let textAlignment: NSTextAlignment
        if annotation?.kind == .text {
            textSize = annotation?.fontSize ?? canvasView.activeTextFontSize
            textAlignment = annotation?.textAlignment ?? .left
        } else {
            textSize = canvasView.activeTextFontSize
            textAlignment = canvasView.activeTextAlignment
        }

        shellViewModel?.apply(
            ScreenshotEditorShellState(
                selectedTool: canvasView.tool,
                inspectorKind: inspectorKind(for: annotation),
                annotationColor: inspectorColor,
                rectangleColor: inspectorColor,
                arrowStrokeWidth: arrowWidth,
                rectangleMode: rectangleMode,
                rectangleStrokeEnabled: rectangleStrokeEnabled,
                detailScale: detailScale,
                lineStyle: lineStyle,
                textSize: textSize,
                textAlignment: textAlignment
            )
        )
    }

    private func inspectorKind(for annotation: ScreenshotEditorAnnotation?) -> ScreenshotEditorInspectorKind {
        if let annotation {
            switch annotation.kind {
            case .arrow:
                return .arrow
            case .line:
                return .line
            case .highlight, .obscure:
                return .rectangle
            case .detail:
                return .detail
            case .text:
                return .text
            }
        }

        switch canvasView.tool {
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
