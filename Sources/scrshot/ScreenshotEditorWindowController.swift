import AppKit

@MainActor
final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    var onComplete: ((CGImage?) -> Void)?

    private let editorViewController: ScreenshotEditorViewController
    private let initialWindowSize: NSSize
    private let preferredDisplayID: CGDirectDisplayID?

    init(image: CGImage, preferredDisplayID: CGDirectDisplayID?) {
        self.preferredDisplayID = preferredDisplayID
        self.editorViewController = ScreenshotEditorViewController(image: image, preferredDisplayID: preferredDisplayID)
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
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.contentViewController = editorViewController
        window.minSize = NSSize(width: 700, height: 520)
        super.init(window: window)

        window.delegate = self
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
        let targetFrame = frameCenteredOnPreferredScreen(size: initialWindowSize)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
        showWindow(nil)
        window.setFrame(targetFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            AppLogger.shared.debug(.editorWindow, "show async before center frame=\(NSStringFromRect(window.frame))")
            window.setFrame(self.frameCenteredOnPreferredScreen(size: self.initialWindowSize), display: true)
            self.centerWindow(window)
            AppLogger.shared.debug(.editorWindow, "show async after center frame=\(NSStringFromRect(window.frame))")
            window.displayIfNeeded()
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                AppLogger.shared.debug(.editorWindow, "show async recenter before frame=\(NSStringFromRect(window.frame))")
                self.centerWindow(window)
                AppLogger.shared.debug(.editorWindow, "show async recenter after frame=\(NSStringFromRect(window.frame))")
                window.displayIfNeeded()
                self.editorViewController.fitContentToWindowIfNeeded()
            }
        }
    }

    func presentVisibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Editor should be open"
        alert.informativeText = "If you do not see the editor window, use Mission Control or hide other windows. The app is trying to bring it to the front again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    private var preferredVisibleFrame: CGRect {
        if let preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func centerWindow(_ window: NSWindow) {
        let visibleFrame = preferredVisibleFrame
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

    private func frameCenteredOnPreferredScreen(size: CGSize) -> CGRect {
        let visibleFrame = preferredVisibleFrame
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
}

private final class FlippedDocumentContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ScreenshotEditorViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onDone: ((CGImage) -> Void)?

    private let document: ScreenshotEditorDocument
    private let documentContainerView = FlippedDocumentContainerView()
    private lazy var canvasView = ScreenshotEditorCanvasView(document: document)
    private let scrollView = NSScrollView()
    private let toolSelector = NSSegmentedControl(
        images: ScreenshotEditorTool.allCases.map { ScreenshotEditorViewController.symbolImage(named: $0.symbolName) },
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let colorWell = NSColorWell()
    private let arrowWidthLabel = NSTextField(labelWithString: "Stroke")
    private let arrowWidthSlider = NSSlider(value: 8, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let rectangleModeLabel = NSTextField(labelWithString: "Rectangle")
    private let rectangleModeControl = NSSegmentedControl(labels: ScreenshotRectangleToolMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let rectangleOpacityLabel = NSTextField(labelWithString: "Opacity")
    private let rectangleOpacitySlider = NSSlider(value: 0.24, minValue: 0.05, maxValue: 1, target: nil, action: nil)
    private let lineStyleLabel = NSTextField(labelWithString: "Line")
    private let lineStylePopupButton = NSPopUpButton()
    private let textSizeLabel = NSTextField(labelWithString: "Text")
    private let textSizeSlider = NSSlider(value: 28, minValue: 12, maxValue: 96, target: nil, action: nil)
    private let textBackgroundButton = NSButton(checkboxWithTitle: "Bg", target: nil, action: nil)
    private let textAlignmentControl = NSSegmentedControl(labels: ["L", "C", "R"], trackingMode: .selectOne, target: nil, action: nil)
    private let fitButton = NSButton(image: ScreenshotEditorViewController.symbolImage(named: "arrow.up.left.and.down.right.magnifyingglass"), target: nil, action: nil)
    private let clearCropButton = NSButton(image: ScreenshotEditorViewController.symbolImage(named: "crop.rotate"), target: nil, action: nil)
    private let editTextButton = NSButton(image: ScreenshotEditorViewController.symbolImage(named: "character.cursor.ibeam"), target: nil, action: nil)
    private let deleteButton = NSButton(image: ScreenshotEditorViewController.symbolImage(named: "trash"), target: nil, action: nil)
    private var hasAppliedInitialFit = false
    private let preferredDisplayID: CGDirectDisplayID?
    private var canvasMargins = CGSize(width: 2, height: 0)
    private var contextPanel: NSView?
    override var undoManager: UndoManager? { canvasView.undoManager }

    init(image: CGImage, preferredDisplayID: CGDirectDisplayID?) {
        self.document = ScreenshotEditorDocument(image: image)
        self.preferredDisplayID = preferredDisplayID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var initialWindowSize: NSSize {
        let visibleFrame = preferredVisibleFrame
        let targetWidth = min(max(visibleFrame.width * 0.58, 920), visibleFrame.width - 80)
        let canvasAspectRatio = document.canvasSize.height / max(document.canvasSize.width, 1)
        let estimatedToolbarHeight: CGFloat = 68
        let fittedContentHeight = targetWidth * canvasAspectRatio
        let targetHeight = min(max(fittedContentHeight + estimatedToolbarHeight, 520), visibleFrame.height - 80)
        return NSSize(width: targetWidth, height: targetHeight)
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let toolbar = makeToolbar()
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

        let stack = NSStackView(views: [toolbar, scrollView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 8

        root.addSubview(stack)
        let safeArea = root.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -4)
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

    private func makeToolbar() -> NSView {
        toolSelector.selectedSegment = ScreenshotEditorTool.allCases.firstIndex(of: .hand) ?? 0
        toolSelector.target = self
        toolSelector.action = #selector(toolChanged(_:))
        toolSelector.segmentStyle = .capsule
        toolSelector.controlSize = .small
        toolSelector.segmentDistribution = .fillEqually
        for (index, tool) in ScreenshotEditorTool.allCases.enumerated() {
            toolSelector.setToolTip(hint(for: tool), forSegment: index)
            toolSelector.setWidth(32, forSegment: index)
        }

        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.color = .systemRed
        colorWell.toolTip = "Annotation Color"

        arrowWidthLabel.stringValue = "Stroke"
        arrowWidthLabel.textColor = .secondaryLabelColor
        arrowWidthSlider.target = self
        arrowWidthSlider.action = #selector(arrowWidthChanged(_:))
        arrowWidthSlider.numberOfTickMarks = 0
        arrowWidthSlider.isContinuous = true
        arrowWidthSlider.controlSize = .small
        arrowWidthSlider.translatesAutoresizingMaskIntoConstraints = false
        arrowWidthSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        arrowWidthLabel.isHidden = false
        arrowWidthSlider.isHidden = false

        rectangleModeLabel.stringValue = "Rectangle"
        rectangleModeLabel.textColor = .secondaryLabelColor
        rectangleModeControl.target = self
        rectangleModeControl.action = #selector(rectangleModeChanged(_:))
        rectangleModeControl.segmentStyle = .capsule
        rectangleModeControl.controlSize = .small
        rectangleModeControl.selectedSegment = 1

        rectangleOpacityLabel.stringValue = "Opacity"
        rectangleOpacityLabel.textColor = .secondaryLabelColor
        rectangleOpacitySlider.target = self
        rectangleOpacitySlider.action = #selector(rectangleOpacityChanged(_:))
        rectangleOpacitySlider.isContinuous = true
        rectangleOpacitySlider.controlSize = .small
        rectangleOpacitySlider.translatesAutoresizingMaskIntoConstraints = false
        rectangleOpacitySlider.widthAnchor.constraint(equalToConstant: 110).isActive = true

        lineStyleLabel.stringValue = "Line"
        lineStyleLabel.textColor = .secondaryLabelColor
        for style in ScreenshotLineStyle.allCases {
            lineStylePopupButton.addItem(withTitle: style.title)
            lineStylePopupButton.lastItem?.representedObject = style
        }
        lineStylePopupButton.target = self
        lineStylePopupButton.action = #selector(lineStyleChanged(_:))
        lineStylePopupButton.controlSize = .small

        textSizeLabel.stringValue = "Text"
        textSizeLabel.textColor = .secondaryLabelColor
        textSizeSlider.target = self
        textSizeSlider.action = #selector(textSizeChanged(_:))
        textSizeSlider.isContinuous = true
        textSizeSlider.controlSize = .small
        textSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        textSizeSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true

        textBackgroundButton.target = self
        textBackgroundButton.action = #selector(textBackgroundChanged(_:))
        textBackgroundButton.title = "Background"
        textBackgroundButton.controlSize = .small

        textAlignmentControl.target = self
        textAlignmentControl.action = #selector(textAlignmentChanged(_:))
        textAlignmentControl.selectedSegment = 0
        textAlignmentControl.segmentStyle = .capsule
        textAlignmentControl.controlSize = .small
        textAlignmentControl.setLabel("Left", forSegment: 0)
        textAlignmentControl.setLabel("Center", forSegment: 1)
        textAlignmentControl.setLabel("Right", forSegment: 2)

        fitButton.target = self
        fitButton.action = #selector(fitTapped)
        configureToolbarButton(fitButton, toolTip: "Fit to Selection")

        clearCropButton.target = self
        clearCropButton.action = #selector(clearCropTapped)
        clearCropButton.isEnabled = false
        configureToolbarButton(clearCropButton, toolTip: "Reset Crop")

        editTextButton.target = self
        editTextButton.action = #selector(editTextTapped)
        editTextButton.isEnabled = false
        configureToolbarButton(editTextButton, toolTip: "Edit Text")

        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.isEnabled = false
        configureToolbarButton(deleteButton, toolTip: "Delete Annotation")

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.controlSize = .small
        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolGroup = makeToolbarGroup([toolSelector])
        let commonGroup = makeToolbarGroup([cancelButton, doneButton])
        let detailGroup = makeToolbarGroup([fitButton, colorWell, arrowWidthLabel, arrowWidthSlider, lineStyleLabel, lineStylePopupButton, rectangleModeLabel, rectangleModeControl, rectangleOpacityLabel, rectangleOpacitySlider, textSizeLabel, textSizeSlider, textBackgroundButton, textAlignmentControl, clearCropButton, editTextButton, deleteButton])
        contextPanel = detailGroup
        detailGroup.isHidden = true

        toolGroup.setContentHuggingPriority(.required, for: .horizontal)
        toolGroup.setContentCompressionResistancePriority(.required, for: .horizontal)
        commonGroup.setContentHuggingPriority(.required, for: .horizontal)
        commonGroup.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailGroup.setContentHuggingPriority(.required, for: .horizontal)
        detailGroup.setContentCompressionResistancePriority(.required, for: .horizontal)

        let toolbar = NSStackView(views: [toolGroup, detailGroup, spacer, commonGroup])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }

    private func configureCanvas() {
        canvasView.tool = .hand
        canvasView.activeColor = colorWell.color
        canvasView.activeArrowStrokeWidth = CGFloat(arrowWidthSlider.doubleValue)
        canvasView.activeRectangleMode = .blur
        canvasView.activeLineStyle = .solid
        canvasView.activeHighlightOpacity = CGFloat(rectangleOpacitySlider.doubleValue)
        canvasView.activeTextFontSize = CGFloat(textSizeSlider.doubleValue)
        canvasView.activeTextShowsBackground = (textBackgroundButton.state == .on)
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
        canvasView.onCropChanged = { [weak self] cropRect in
            self?.clearCropButton.isEnabled = cropRect != nil
        }
        updateInspector(for: nil)
    }

    @objc
    private func toolChanged(_ sender: NSSegmentedControl) {
        let tool = ScreenshotEditorTool.allCases[sender.selectedSegment]
        canvasView.tool = tool
        updateInspector(for: canvasView.selectedAnnotation)
        view.window?.makeFirstResponder(canvasView)
    }

    @objc
    private func cancelTapped() {
        onCancel?()
    }

    @objc
    private func doneTapped() {
        guard let image = canvasView.makeRenderedImage() else {
            NSSound.beep()
            return
        }
        onDone?(image)
    }

    @objc
    private func colorChanged(_ sender: NSColorWell) {
        canvasView.applyColor(sender.color)
        updateInspector(for: canvasView.selectedAnnotation)
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
    private func arrowWidthChanged(_ sender: NSSlider) {
        canvasView.applyArrowStrokeWidth(CGFloat(sender.doubleValue))
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func rectangleModeChanged(_ sender: NSSegmentedControl) {
        let mode = ScreenshotRectangleToolMode.allCases[max(sender.selectedSegment, 0)]
        canvasView.applyRectangleMode(mode)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func rectangleOpacityChanged(_ sender: NSSlider) {
        canvasView.applyHighlightOpacity(CGFloat(sender.doubleValue))
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func lineStyleChanged(_ sender: NSPopUpButton) {
        guard let style = sender.selectedItem?.representedObject as? ScreenshotLineStyle else { return }
        canvasView.applyLineStyle(style)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func textSizeChanged(_ sender: NSSlider) {
        canvasView.applyTextFontSize(CGFloat(sender.doubleValue))
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func textBackgroundChanged(_ sender: NSButton) {
        canvasView.applyTextBackground(sender.state == .on)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func textAlignmentChanged(_ sender: NSSegmentedControl) {
        let alignment: NSTextAlignment
        switch sender.selectedSegment {
        case 1:
            alignment = .center
        case 2:
            alignment = .right
        default:
            alignment = .left
        }
        canvasView.applyTextAlignment(alignment)
        updateInspector(for: canvasView.selectedAnnotation)
    }

    @objc
    private func clearCropTapped() {
        canvasView.clearCrop()
        fitContentToWindow()
    }

    @objc
    private func editTextTapped() {
        canvasView.editSelectedText()
    }

    @objc
    private func deleteTapped() {
        canvasView.deleteSelection()
        updateInspector(for: canvasView.selectedAnnotation)
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

    private func hint(for tool: ScreenshotEditorTool) -> String {
        switch tool {
        case .hand:
            return "Drag to move around the screenshot."
        case .crop:
            return "Drag to crop the current image."
        case .arrow:
            return "Drag to place a red arrow."
        case .line:
            return "Drag to place a line with horizontal or vertical snap."
        case .rectangle:
            return "Drag to create a tinted, blurred, or black rectangle."
        case .text:
            return "Click to place text and type inline."
        }
    }

    private var preferredVisibleFrame: CGRect {
        if let preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func applyInitialFitIfNeeded(force: Bool = false) {
        guard force || !hasAppliedInitialFit else { return }
        let viewportSize = viewportSize
        guard viewportSize.width > 1, viewportSize.height > 1 else {
            return
        }
        hasAppliedInitialFit = true
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
        // Fit must be deterministic. Animating magnification and then immediately centering
        // causes the clip view to use stale geometry for one frame, which breaks crop fit.
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
        let horizontalMargin = max(min(visibleSize.width * 0.005, 4), 2)
        let verticalMargin: CGFloat = 0
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

    private func configureToolbarButton(_ button: NSButton, toolTip: String) {
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.contentTintColor = .labelColor
    }

    private func makeToolbarGroup(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        let container = NSVisualEffectView()
        container.material = .sidebar
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func symbolImage(named systemName: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage()
        return image.withSymbolConfiguration(configuration) ?? image
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
        deleteButton.isEnabled = annotation != nil
        editTextButton.isEnabled = annotation?.kind == .text
        clearCropButton.isEnabled = canvasView.cropRect != nil
        let selectedKind = annotation?.kind
        let isRectangleHighlight = selectedKind == .highlight
        let showsColorControl: Bool
        if let selectedKind {
            showsColorControl = selectedKind == .arrow || selectedKind == .line || selectedKind == .highlight || selectedKind == .text
        } else {
            showsColorControl =
                canvasView.tool == .arrow ||
                canvasView.tool == .line ||
                canvasView.tool == .text ||
                (canvasView.tool == .rectangle && canvasView.activeRectangleMode == .highlight)
        }
        colorWell.isHidden = !showsColorControl
        if let annotation, annotation.kind != .obscure {
            colorWell.color = annotation.color
        } else {
            colorWell.color = canvasView.activeColor
        }

        let showsArrowControls =
            annotation?.kind == .arrow ||
            annotation?.kind == .line ||
            annotation?.kind == .highlight ||
            (annotation == nil && (canvasView.tool == .arrow || canvasView.tool == .line || (canvasView.tool == .rectangle && canvasView.activeRectangleMode == .highlight)))
        arrowWidthLabel.isHidden = !showsArrowControls
        arrowWidthSlider.isHidden = !showsArrowControls
        if annotation?.kind == .arrow || annotation?.kind == .line || annotation?.kind == .highlight {
            arrowWidthSlider.doubleValue = Double(annotation?.strokeWidth ?? 6)
        } else {
            arrowWidthSlider.doubleValue = Double(canvasView.activeArrowStrokeWidth)
        }

        let showsLineStyleControls = annotation?.kind == .line || (annotation == nil && canvasView.tool == .line)
        lineStyleLabel.isHidden = !showsLineStyleControls
        lineStylePopupButton.isHidden = !showsLineStyleControls
        if annotation?.kind == .line {
            lineStylePopupButton.selectItem(at: ScreenshotLineStyle.allCases.firstIndex(of: annotation?.lineStyle ?? .solid) ?? 0)
        } else {
            lineStylePopupButton.selectItem(at: ScreenshotLineStyle.allCases.firstIndex(of: canvasView.activeLineStyle) ?? 0)
        }

        let showsRectangleControls = annotation?.kind == .highlight || annotation?.kind == .obscure || (annotation == nil && canvasView.tool == .rectangle)
        rectangleModeLabel.isHidden = !showsRectangleControls
        rectangleModeControl.isHidden = !showsRectangleControls
        let rectangleMode: ScreenshotRectangleToolMode
        if annotation?.kind == .highlight {
            rectangleMode = .highlight
        } else if annotation?.kind == .obscure {
            rectangleMode = annotation?.obscureStyle == .blur ? .blur : .redact
        } else {
            rectangleMode = canvasView.activeRectangleMode
        }
        rectangleModeControl.selectedSegment = ScreenshotRectangleToolMode.allCases.firstIndex(of: rectangleMode) ?? 0

        let showsRectangleOpacityControls = isRectangleHighlight || (annotation == nil && canvasView.tool == .rectangle && canvasView.activeRectangleMode == .highlight)
        rectangleOpacityLabel.isHidden = !showsRectangleOpacityControls
        rectangleOpacitySlider.isHidden = !showsRectangleOpacityControls
        if annotation?.kind == .highlight {
            rectangleOpacitySlider.doubleValue = Double(annotation?.fillOpacity ?? canvasView.activeHighlightOpacity)
        } else {
            rectangleOpacitySlider.doubleValue = Double(canvasView.activeHighlightOpacity)
        }

        let showsTextControls = annotation?.kind == .text || (annotation == nil && canvasView.tool == .text)
        textSizeLabel.isHidden = !showsTextControls
        textSizeSlider.isHidden = !showsTextControls
        textBackgroundButton.isHidden = !showsTextControls
        textAlignmentControl.isHidden = !showsTextControls
        fitButton.isHidden = canvasView.tool != .crop
        clearCropButton.isHidden = !(canvasView.tool == .crop || canvasView.cropRect != nil)
        editTextButton.isHidden = !showsTextControls
        deleteButton.isHidden = annotation == nil
        if annotation?.kind == .text {
            textSizeSlider.doubleValue = Double(annotation?.fontSize ?? canvasView.activeTextFontSize)
            textBackgroundButton.state = (annotation?.showsTextBackground ?? canvasView.activeTextShowsBackground) ? .on : .off
            switch annotation?.textAlignment ?? .left {
            case .center:
                textAlignmentControl.selectedSegment = 1
            case .right:
                textAlignmentControl.selectedSegment = 2
            default:
                textAlignmentControl.selectedSegment = 0
            }
        } else {
            textSizeSlider.doubleValue = Double(canvasView.activeTextFontSize)
            textBackgroundButton.state = canvasView.activeTextShowsBackground ? .on : .off
            switch canvasView.activeTextAlignment {
            case .center:
                textAlignmentControl.selectedSegment = 1
            case .right:
                textAlignmentControl.selectedSegment = 2
            default:
                textAlignmentControl.selectedSegment = 0
            }
        }

        let visibleContextControls = [
            !colorWell.isHidden,
            !arrowWidthLabel.isHidden,
            !arrowWidthSlider.isHidden,
            !lineStyleLabel.isHidden,
            !lineStylePopupButton.isHidden,
            !rectangleModeLabel.isHidden,
            !rectangleModeControl.isHidden,
            !rectangleOpacityLabel.isHidden,
            !rectangleOpacitySlider.isHidden,
            !textSizeLabel.isHidden,
            !textSizeSlider.isHidden,
            !textBackgroundButton.isHidden,
            !textAlignmentControl.isHidden,
            !clearCropButton.isHidden,
            !editTextButton.isHidden,
            !deleteButton.isHidden
        ].contains(true)
        contextPanel?.isHidden = !visibleContextControls
    }
}
