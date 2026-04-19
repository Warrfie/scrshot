import XCTest
import ImageIO
import CoreGraphics
import AppKit
import Carbon
@testable import scrshot

final class ScreenCaptureServiceTests: XCTestCase {
    func testCropReturnsExpectedSubimagePixels() throws {
        let image = makeImage(
            width: 4,
            height: 4,
            pixels: [
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0),
            ]
        )
        let screen = ScreenCaptureService.CapturedScreen(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 4, height: 4),
            image: image,
            scaleX: 1,
            scaleY: 1
        )

        let result = try ScreenCaptureService().crop(
            selection: CGRect(x: 2, y: 0, width: 2, height: 2),
            from: [screen]
        )

        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(pixel(atX: 0, y: 0, in: result), rgba(255, 255, 0))
        XCTAssertEqual(pixel(atX: 1, y: 1, in: result), rgba(255, 255, 0))
    }

    func testCompositeImageUnionsScreens() throws {
        let left = makeImage(width: 2, height: 2, pixels: Array(repeating: rgba(255, 0, 0), count: 4))
        let right = makeImage(width: 2, height: 2, pixels: Array(repeating: rgba(0, 255, 0), count: 4))
        let screens = [
            ScreenCaptureService.CapturedScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 2, height: 2), image: left, scaleX: 1, scaleY: 1),
            ScreenCaptureService.CapturedScreen(displayID: 2, frame: CGRect(x: 2, y: 0, width: 2, height: 2), image: right, scaleX: 1, scaleY: 1),
        ]

        let result = try ScreenCaptureService().compositeImage(from: screens)

        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(pixel(atX: 0, y: 0, in: result), rgba(255, 0, 0))
        XCTAssertEqual(pixel(atX: 3, y: 1, in: result), rgba(0, 255, 0))
    }

    func testCropOutsideVisibleScreensThrows() {
        let image = makeImage(width: 2, height: 2, pixels: Array(repeating: rgba(255, 0, 0), count: 4))
        let screen = ScreenCaptureService.CapturedScreen(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            image: image,
            scaleX: 1,
            scaleY: 1
        )

        XCTAssertThrowsError(
            try ScreenCaptureService().crop(selection: CGRect(x: 5, y: 5, width: 1, height: 1), from: [screen])
        ) { error in
            guard case ScreenCaptureService.CaptureError.selectionOutsideVisibleScreens = error else {
                return XCTFail("Expected selectionOutsideVisibleScreens, got \(error)")
            }
        }
    }

    func testPermissionControllerRequestsSystemPromptOnlyOncePerLaunchInstance() {
        var requestCallCount = 0
        let controller = ScreenCapturePermissionController(
            preflightAccess: { false },
            requestAccess: {
                requestCallCount += 1
                return false
            }
        )

        XCTAssertFalse(controller.hasAccess)
        XCTAssertFalse(controller.hasRequestedSystemPrompt)
        XCTAssertFalse(controller.requestAccessIfNeeded())
        XCTAssertEqual(requestCallCount, 1)
        XCTAssertTrue(controller.hasRequestedSystemPrompt)
    }

    func testCaptureCurrentDisplayDoesNotRePromptAfterInitialPermissionRequest() {
        var requestCallCount = 0
        let permissionController = ScreenCapturePermissionController(
            preflightAccess: { false },
            requestAccess: {
                requestCallCount += 1
                return false
            }
        )
        let service = ScreenCaptureService(permissionController: permissionController)

        XCTAssertThrowsError(try service.captureCurrentDisplay()) { error in
            guard case ScreenCaptureService.CaptureError.screenRecordingPermissionDenied = error else {
                return XCTFail("Expected screenRecordingPermissionDenied, got \(error)")
            }
        }
        XCTAssertEqual(requestCallCount, 1)

        XCTAssertThrowsError(try service.captureCurrentDisplay()) { error in
            guard case ScreenCaptureService.CaptureError.screenRecordingPermissionDenied = error else {
                return XCTFail("Expected screenRecordingPermissionDenied, got \(error)")
            }
        }
        XCTAssertEqual(requestCallCount, 1)
    }

    @MainActor
    func testMicrophonePermissionControllerRequestsSystemPromptOnlyOncePerLaunchInstance() async {
        var requestCallCount = 0
        let controller = MicrophonePermissionController(
            authorizationStatusProvider: { .notDetermined },
            requestAccess: {
                requestCallCount += 1
                return false
            }
        )

        XCTAssertFalse(controller.hasAccess)
        XCTAssertFalse(controller.hasRequestedSystemPrompt)
        let initialRequestResult = await controller.requestAccessIfNeeded()
        XCTAssertFalse(initialRequestResult)
        XCTAssertEqual(requestCallCount, 1)
        XCTAssertTrue(controller.hasRequestedSystemPrompt)
    }

    @MainActor
    func testPermissionPreflightOnLaunchDoesNotOpenSystemSettingsWhenDenied() async {
        let screenCapturePermissionController = ScreenCapturePermissionController(
            preflightAccess: { false },
            requestAccess: { false },
            activateApp: {}
        )
        let microphonePermissionController = MicrophonePermissionController(
            authorizationStatusProvider: { .notDetermined },
            requestAccess: { false },
            activateApp: {}
        )
        var openedAnchors: [String] = []
        let coordinator = AppPermissionCoordinator(
            screenCapturePermissionController: screenCapturePermissionController,
            microphonePermissionController: microphonePermissionController,
            openPrivacyPane: { openedAnchors.append($0) }
        )

        coordinator.preflightOnLaunch(recordingAudioSource: .systemAudioAndMicrophone)
        await Task.yield()

        XCTAssertTrue(openedAnchors.isEmpty)
    }

    @MainActor
    func testEnsurePermissionsForCaptureOpensSystemSettingsWhenDenied() {
        let screenCapturePermissionController = ScreenCapturePermissionController(
            preflightAccess: { false },
            requestAccess: { false },
            activateApp: {}
        )
        var openedAnchors: [String] = []
        let coordinator = AppPermissionCoordinator(
            screenCapturePermissionController: screenCapturePermissionController,
            microphonePermissionController: MicrophonePermissionController(
                authorizationStatusProvider: { .authorized },
                requestAccess: { true },
                activateApp: {}
            ),
            openPrivacyPane: { openedAnchors.append($0) }
        )

        let granted = coordinator.ensurePermissionsForCapture()

        XCTAssertFalse(granted)
        XCTAssertEqual(openedAnchors, ["Privacy_ScreenCapture"])
    }

    @MainActor
    func testEnsurePermissionsForCaptureReturnsTrueWhenPermissionAlreadyGranted() {
        let coordinator = AppPermissionCoordinator(
            screenCapturePermissionController: ScreenCapturePermissionController(
                preflightAccess: { true },
                requestAccess: { true },
                activateApp: {}
            ),
            microphonePermissionController: MicrophonePermissionController(
                authorizationStatusProvider: { .authorized },
                requestAccess: { true },
                activateApp: {}
            ),
            openPrivacyPane: { _ in XCTFail("Should not open System Settings when permission is already granted") }
        )

        XCTAssertTrue(coordinator.ensurePermissionsForCapture())
    }

    @MainActor
    func testEnsurePermissionsForRecordingReturnsFalseWhenScreenCapturePermissionDenied() async {
        let coordinator = AppPermissionCoordinator(
            screenCapturePermissionController: ScreenCapturePermissionController(
                preflightAccess: { false },
                requestAccess: { false },
                activateApp: {}
            ),
            microphonePermissionController: MicrophonePermissionController(
                authorizationStatusProvider: { .authorized },
                requestAccess: { true },
                activateApp: {}
            ),
            openPrivacyPane: { _ in }
        )

        let granted = await coordinator.ensurePermissionsForRecording(audioSource: .systemAudio)
        XCTAssertFalse(granted)
    }
}

@MainActor
final class ScreenshotEditorDocumentTests: XCTestCase {
    func testApplyCropUpdatesFocusRectAndRenderedImageSize() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 10, height: 10, pixels: Array(repeating: rgba(10, 20, 30), count: 100)))

        XCTAssertTrue(document.applyCrop(CGRect(x: 2.2, y: 3.7, width: 4.4, height: 2.1)))
        XCTAssertEqual(document.focusRect, CGRect(x: 2, y: 3, width: 5, height: 3))

        let rendered = document.renderedImage()
        XCTAssertEqual(rendered?.width, 5)
        XCTAssertEqual(rendered?.height, 3)
    }

    func testRenderedImageCropsBottomLeftRegionUsingCanvasCoordinates() {
        let image = makeImage(
            width: 6,
            height: 6,
            pixels: [
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0), rgba(255, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0), rgba(255, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0), rgba(255, 255, 0),
            ]
        )
        let document = ScreenshotEditorDocument(image: image)

        XCTAssertTrue(document.applyCrop(CGRect(x: 0, y: 3, width: 3, height: 3)))

        let rendered = document.renderedImage()

        XCTAssertEqual(rendered?.width, 3)
        XCTAssertEqual(rendered?.height, 3)
        XCTAssertEqual(pixel(atX: 0, y: 0, in: rendered!), rgba(0, 0, 255))
        XCTAssertEqual(pixel(atX: 2, y: 2, in: rendered!), rgba(0, 0, 255))
    }

    func testRenderedImagePreservesBaseImageOrientationWithoutAnnotations() {
        let image = makeImage(
            width: 4,
            height: 4,
            pixels: [
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0),
            ]
        )
        let document = ScreenshotEditorDocument(image: image)

        let rendered = try! XCTUnwrap(document.renderedImage())

        XCTAssertEqual(pixel(atX: 0, y: 0, in: rendered), rgba(255, 0, 0))
        XCTAssertEqual(pixel(atX: 3, y: 0, in: rendered), rgba(0, 255, 0))
        XCTAssertEqual(pixel(atX: 0, y: 3, in: rendered), rgba(0, 0, 255))
        XCTAssertEqual(pixel(atX: 3, y: 3, in: rendered), rgba(255, 255, 0))
    }

    func testMoveCropClampsToCanvasBounds() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 10, height: 10, pixels: Array(repeating: rgba(1, 1, 1), count: 100)))
        XCTAssertTrue(document.applyCrop(CGRect(x: 7, y: 7, width: 3, height: 3)))

        document.moveCrop(by: CGPoint(x: 5, y: 5))

        XCTAssertEqual(document.cropRect, CGRect(x: 7, y: 7, width: 3, height: 3))
    }

    func testTextFormattingUpdatesClampToExpectedRanges() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(1, 1, 1), count: 400)))
        let annotation = ScreenshotEditorAnnotation.text(
            "Hello",
            at: CGPoint(x: 2, y: 2),
            color: .systemRed,
            fontSize: 20,
            alignment: .left,
            showsBackground: true
        )
        document.addAnnotation(annotation)

        document.updateSelectedTextFontSize(400)
        document.updateSelectedTextAlignment(.right)
        document.updateSelectedTextBackground(false)

        XCTAssertEqual(document.selectedAnnotation?.fontSize, 96)
        XCTAssertEqual(document.selectedAnnotation?.textAlignment, .right)
        XCTAssertEqual(document.selectedAnnotation?.showsTextBackground, false)
    }

    func testRenderedImageIncludesHighlightAnnotation() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(255, 255, 255), count: 400)))
        document.addAnnotation(.highlight(CGRect(x: 4, y: 4, width: 10, height: 10), color: .systemRed))

        let rendered = document.renderedImage()

        XCTAssertNotNil(rendered)
        XCTAssertNotEqual(pixel(atX: 4, y: 4, in: rendered!), rgba(255, 255, 255))
    }

    func testRenderedImageKeepsHighlightInTopLeftInsteadOfMirroringVertically() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 12, height: 12, pixels: Array(repeating: rgba(255, 255, 255), count: 144)))
        document.addAnnotation(.highlight(CGRect(x: 1, y: 1, width: 4, height: 4), color: .systemRed))

        let rendered = document.renderedImage()!

        XCTAssertNotEqual(pixel(atX: 2, y: 2, in: rendered), rgba(255, 255, 255))
        XCTAssertEqual(pixel(atX: 2, y: 9, in: rendered), rgba(255, 255, 255))
    }

    func testSelectionDeleteButtonRectSitsNearTopRightOfSelectionBounds() {
        let annotation = ScreenshotEditorAnnotation.highlight(
            CGRect(x: 20, y: 30, width: 80, height: 40),
            color: .systemRed
        )

        let buttonRect = annotation.deleteButtonRect(scale: 1)

        XCTAssertGreaterThan(buttonRect.midX, annotation.selectionBounds.midX)
        XCTAssertLessThan(buttonRect.midY, annotation.selectionBounds.midY)
        XCTAssertGreaterThan(buttonRect.width, 0)
        XCTAssertGreaterThan(buttonRect.height, 0)
    }

    func testCropDeleteButtonRectSitsNearTopRightOfCropBounds() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 200, height: 120, pixels: Array(repeating: rgba(255, 255, 255), count: 24_000)))
        let canvasView = ScreenshotEditorCanvasView(document: document)
        let cropRect = CGRect(x: 20, y: 30, width: 80, height: 40)

        let buttonRect = canvasView.cropDeleteButtonRect(for: cropRect, scale: 1)

        XCTAssertGreaterThan(buttonRect.midX, cropRect.midX)
        XCTAssertLessThan(buttonRect.midY, cropRect.midY)
        XCTAssertGreaterThan(buttonRect.width, 0)
        XCTAssertGreaterThan(buttonRect.height, 0)
    }

    func testUpdateSelectedColorChangesRenderedHighlightColor() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(255, 255, 255), count: 400)))
        let originalColor = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
        let updatedColor = NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
        let annotation = ScreenshotEditorAnnotation.highlight(CGRect(x: 4, y: 4, width: 10, height: 10), color: originalColor)
        document.addAnnotation(annotation)

        let initialPixel = pixel(atX: 6, y: 6, in: document.renderedImage()!)
        document.updateSelectedColor(updatedColor)
        let updatedPixel = pixel(atX: 6, y: 6, in: document.renderedImage()!)

        XCTAssertNotEqual(initialPixel, updatedPixel)
        XCTAssertGreaterThan(updatedPixel.b, updatedPixel.r)
    }

    func testRenderedImageIncludesRedactAnnotation() {
        let basePixels = Array(repeating: rgba(230, 230, 230), count: 40 * 40)
        let document = ScreenshotEditorDocument(image: makeImage(width: 40, height: 40, pixels: basePixels))
        document.addAnnotation(.obscure(CGRect(x: 8, y: 8, width: 16, height: 16), style: .redact))

        let rendered = document.renderedImage()

        XCTAssertEqual(pixel(atX: 16, y: 16, in: rendered!), rgba(0, 0, 0))
    }

    func testRenderedImageKeepsRedactInTopLeftInsteadOfMirroringVertically() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 12, height: 12, pixels: Array(repeating: rgba(255, 255, 255), count: 144)))
        document.addAnnotation(.obscure(CGRect(x: 1, y: 1, width: 4, height: 4), style: .redact))

        let rendered = document.renderedImage()!

        XCTAssertEqual(pixel(atX: 2, y: 2, in: rendered), rgba(0, 0, 0))
        XCTAssertEqual(pixel(atX: 2, y: 9, in: rendered), rgba(255, 255, 255))
    }

    func testRenderedImageKeepsArrowNearTopEdgeInsteadOfMirroringVertically() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(255, 255, 255), count: 400)))
        document.addAnnotation(.arrow(
            from: CGPoint(x: 2, y: 2),
            to: CGPoint(x: 16, y: 2),
            color: .black
        ))

        let rendered = document.renderedImage()!

        XCTAssertNotEqual(pixel(atX: 10, y: 2, in: rendered), rgba(255, 255, 255))
        XCTAssertEqual(pixel(atX: 10, y: 17, in: rendered), rgba(255, 255, 255))
    }

    func testRenderedImageKeepsArrowHeadAtEndPoint() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 80, height: 40, pixels: Array(repeating: rgba(255, 255, 255), count: 3_200)))
        var annotation = ScreenshotEditorAnnotation.arrow(
            from: CGPoint(x: 10, y: 20),
            to: CGPoint(x: 60, y: 20),
            color: .black
        )
        annotation.strokeWidth = 4
        document.addAnnotation(annotation)

        let rendered = document.renderedImage()!
        let startHeadAreaPixel = pixel(atX: 20, y: 14, in: rendered)
        let endHeadAreaPixel = pixel(atX: 50, y: 14, in: rendered)

        XCTAssertEqual(startHeadAreaPixel, rgba(255, 255, 255))
        XCTAssertNotEqual(endHeadAreaPixel, rgba(255, 255, 255))
    }

    func testArrowExportAdjustmentPreservesStartAndEndAfterVerticalFlip() {
        let annotation = ScreenshotEditorAnnotation.arrow(
            from: CGPoint(x: 12, y: 16),
            to: CGPoint(x: 60, y: 54),
            color: .black
        )

        let adjusted = annotation.exportAdjusted(forCanvasHeight: 80)

        XCTAssertEqual(adjusted.startPoint, CGPoint(x: 12, y: 64))
        XCTAssertEqual(adjusted.endPoint, CGPoint(x: 60, y: 26))
    }

    func testLineExportAdjustmentPreservesStartAndEndAfterVerticalFlip() {
        let annotation = ScreenshotEditorAnnotation.line(
            from: CGPoint(x: 10, y: 14),
            to: CGPoint(x: 58, y: 62),
            color: .black
        )

        let adjusted = annotation.exportAdjusted(forCanvasHeight: 80)

        XCTAssertEqual(adjusted.startPoint, CGPoint(x: 10, y: 66))
        XCTAssertEqual(adjusted.endPoint, CGPoint(x: 58, y: 66))
    }

    func testRenderedImageKeepsLineNearTopEdgeInsteadOfMirroringVertically() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(255, 255, 255), count: 400)))
        document.addAnnotation(.line(
            from: CGPoint(x: 2, y: 2),
            to: CGPoint(x: 16, y: 2),
            color: .black
        ))

        let rendered = document.renderedImage()!

        XCTAssertNotEqual(pixel(atX: 10, y: 2, in: rendered), rgba(255, 255, 255))
        XCTAssertEqual(pixel(atX: 10, y: 17, in: rendered), rgba(255, 255, 255))
    }

    func testRenderedImagePreservesDiagonalLineGeometryWhenSaving() {
        let baseImage = makeImage(width: 80, height: 80, pixels: Array(repeating: rgba(255, 255, 255), count: 6_400))
        let document = ScreenshotEditorDocument(image: baseImage)
        let annotation = ScreenshotEditorAnnotation.line(
            from: CGPoint(x: 10, y: 14),
            to: CGPoint(x: 58, y: 62),
            color: .black
        )
        document.addAnnotation(annotation)

        let rendered = document.renderedImage()!
        XCTAssertNotEqual(pixel(atX: 20, y: 14, in: rendered), rgba(255, 255, 255))
        XCTAssertNotEqual(pixel(atX: 48, y: 14, in: rendered), rgba(255, 255, 255))
        XCTAssertEqual(pixel(atX: 20, y: 65, in: rendered), rgba(255, 255, 255))
    }

    func testRenderedImagePreservesDiagonalArrowGeometryWhenSaving() {
        let baseImage = makeImage(width: 80, height: 80, pixels: Array(repeating: rgba(255, 255, 255), count: 6_400))
        let document = ScreenshotEditorDocument(image: baseImage)
        let annotation = ScreenshotEditorAnnotation.arrow(
            from: CGPoint(x: 12, y: 16),
            to: CGPoint(x: 60, y: 54),
            color: .black
        )
        document.addAnnotation(annotation)

        let rendered = document.renderedImage()!
        XCTAssertNotEqual(pixel(atX: 24, y: 26, in: rendered), rgba(255, 255, 255))
        XCTAssertNotEqual(pixel(atX: 48, y: 46, in: rendered), rgba(255, 255, 255))
        XCTAssertEqual(pixel(atX: 24, y: 54, in: rendered), rgba(255, 255, 255))
        XCTAssertNotEqual(pixel(atX: 54, y: 42, in: rendered), rgba(255, 255, 255))
    }

    func testRenderedImageIncludesBlurAnnotation() {
        var basePixels: [RGBA] = []
        for y in 0..<40 {
            for x in 0..<40 {
                basePixels.append((x + y).isMultiple(of: 2) ? rgba(0, 0, 0) : rgba(255, 255, 255))
            }
        }

        let baseImage = makeImage(width: 40, height: 40, pixels: basePixels)
        let plainDocument = ScreenshotEditorDocument(image: baseImage)
        let blurredDocument = ScreenshotEditorDocument(image: baseImage)
        blurredDocument.addAnnotation(.obscure(CGRect(x: 8, y: 8, width: 16, height: 16), style: .blur))

        let plainRendered = plainDocument.renderedImage()!
        let blurredRendered = blurredDocument.renderedImage()!

        XCTAssertGreaterThan(differingPixelCount(between: plainRendered, and: blurredRendered), 40)
    }

    func testRenderedImageIncludesDetailCalloutAnnotation() {
        var basePixels: [RGBA] = []
        for y in 0..<120 {
            for x in 0..<160 {
                basePixels.append(rgba(UInt8((x * 3) % 255), UInt8((y * 5) % 255), UInt8(((x + y) * 7) % 255)))
            }
        }

        let baseImage = makeImage(width: 160, height: 120, pixels: basePixels)
        let plainDocument = ScreenshotEditorDocument(image: baseImage)
        let detailDocument = ScreenshotEditorDocument(image: baseImage)
        detailDocument.addAnnotation(.detail(
            sourcePoint: CGPoint(x: 36, y: 34),
            bubbleCenter: CGPoint(x: 118, y: 82),
            color: .systemRed,
            scale: 2.4
        ))

        let plainRendered = plainDocument.renderedImage()!
        let detailRendered = detailDocument.renderedImage()!

        XCTAssertGreaterThan(differingPixelCount(between: plainRendered, and: detailRendered), 900)
    }

    func testDetailCalloutZoomChangesSourceMarkerAndMagnifiedContent() {
        var basePixels: [RGBA] = []
        for y in 0..<140 {
            for x in 0..<180 {
                basePixels.append(rgba(UInt8((x * 11) % 255), UInt8((y * 7) % 255), UInt8(((x * 3) + (y * 5)) % 255)))
            }
        }

        let baseImage = makeImage(width: 180, height: 140, pixels: basePixels)
        let lowZoomDocument = ScreenshotEditorDocument(image: baseImage)
        lowZoomDocument.addAnnotation(.detail(
            sourcePoint: CGPoint(x: 44, y: 42),
            bubbleCenter: CGPoint(x: 132, y: 94),
            color: .systemBlue,
            scale: 1.5
        ))

        let highZoomDocument = ScreenshotEditorDocument(image: baseImage)
        highZoomDocument.addAnnotation(.detail(
            sourcePoint: CGPoint(x: 44, y: 42),
            bubbleCenter: CGPoint(x: 132, y: 94),
            color: .systemBlue,
            scale: 4.5
        ))

        let lowZoomRendered = lowZoomDocument.renderedImage()!
        let highZoomRendered = highZoomDocument.renderedImage()!

        XCTAssertGreaterThan(differingPixelCount(between: lowZoomRendered, and: highZoomRendered), 700)
    }

    func testDetailCalloutCentersTheSameSourceRegionShownInSourceMarker() {
        let width = 180
        let height = 180
        var basePixels = Array(repeating: rgba(12, 12, 12), count: width * height)

        for y in 34..<50 {
            for x in 36..<52 {
                basePixels[y * width + x] = rgba(255, 40, 40)
            }
        }

        for y in 118..<134 {
            for x in 36..<52 {
                basePixels[y * width + x] = rgba(40, 255, 40)
            }
        }

        let baseImage = makeImage(width: width, height: height, pixels: basePixels)
        let document = ScreenshotEditorDocument(image: baseImage)
        document.addAnnotation(.detail(
            sourcePoint: CGPoint(x: 44, y: 42),
            bubbleCenter: CGPoint(x: 128, y: 92),
            color: .systemRed,
            scale: 6
        ))

        let rendered = document.renderedImage()!
        let bubbleCenterPixel = pixel(atX: 128, y: 92, in: rendered)

        XCTAssertGreaterThan(Int(bubbleCenterPixel.r), 200)
        XCTAssertLessThan(Int(bubbleCenterPixel.g), 120)
    }

    func testDetailCalloutPreservesVerticalOrientationInsideBubble() {
        let width = 160
        let height = 160
        var basePixels = Array(repeating: rgba(18, 18, 18), count: width * height)

        for y in 32..<44 {
            for x in 34..<54 {
                basePixels[y * width + x] = rgba(255, 40, 40)
            }
        }

        for y in 44..<56 {
            for x in 34..<54 {
                basePixels[y * width + x] = rgba(40, 255, 40)
            }
        }

        let baseImage = makeImage(width: width, height: height, pixels: basePixels)
        let document = ScreenshotEditorDocument(image: baseImage)
        document.addAnnotation(.detail(
            sourcePoint: CGPoint(x: 44, y: 44),
            bubbleCenter: CGPoint(x: 116, y: 96),
            color: .systemRed,
            scale: 5
        ))

        let rendered = document.renderedImage()!
        let upperBubblePixel = pixel(atX: 116, y: 82, in: rendered)
        let lowerBubblePixel = pixel(atX: 116, y: 110, in: rendered)

        XCTAssertGreaterThan(Int(upperBubblePixel.r), Int(upperBubblePixel.g))
        XCTAssertGreaterThan(Int(lowerBubblePixel.g), Int(lowerBubblePixel.r))
    }

    func testCropAndAnnotationRenderTogether() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(240, 240, 240), count: 400)))
        document.addAnnotation(.highlight(CGRect(x: 2, y: 2, width: 8, height: 8), color: .systemBlue))
        XCTAssertTrue(document.applyCrop(CGRect(x: 1, y: 1, width: 6, height: 6)))

        let rendered = document.renderedImage()

        XCTAssertEqual(rendered?.width, 6)
        XCTAssertEqual(rendered?.height, 6)
        XCTAssertNotEqual(pixel(atX: 1, y: 1, in: rendered!), rgba(240, 240, 240))
    }

    func testUpdateTextLayoutUpdatesAnnotationSize() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(1, 1, 1), count: 400)))
        let annotation = ScreenshotEditorAnnotation.text(
            "Hello",
            at: CGPoint(x: 3, y: 4),
            color: .systemRed,
            fontSize: 18,
            alignment: .left,
            showsBackground: true
        )
        document.addAnnotation(annotation)

        document.updateTextLayout(for: annotation.id, size: CGSize(width: 180, height: 72))

        XCTAssertEqual(document.selectedAnnotation?.rect.origin, CGPoint(x: 3, y: 4))
        XCTAssertEqual(document.selectedAnnotation?.rect.size, CGSize(width: 180, height: 72))
    }

    func testUndoRedoRestoresAnnotationState() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 20, height: 20, pixels: Array(repeating: rgba(1, 1, 1), count: 400)))

        document.performUndoableChange(actionName: "Add Highlight") {
            document.addAnnotation(.highlight(CGRect(x: 2, y: 2, width: 4, height: 4), color: .systemYellow))
        }

        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertTrue(document.canUndo)

        document.undo()
        XCTAssertTrue(document.annotations.isEmpty)

        document.redo()
        XCTAssertEqual(document.annotations.count, 1)
    }

    func testUndoRedoAcrossMultipleSequentialOperationsRestoresStateInOrder() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 40, height: 40, pixels: Array(repeating: rgba(255, 255, 255), count: 1600)))

        let annotation = ScreenshotEditorAnnotation.text(
            "One",
            at: CGPoint(x: 4, y: 4),
            color: .systemRed,
            fontSize: 18,
            alignment: .left,
            showsBackground: false
        )

        document.performUndoableChange(actionName: "Add Text") {
            document.addAnnotation(annotation)
        }
        document.performUndoableChange(actionName: "Resize Text") {
            document.updateTextLayout(for: annotation.id, size: CGSize(width: 150, height: 44))
        }
        document.performUndoableChange(actionName: "Style Text") {
            document.updateSelectedTextBackground(true)
            document.updateSelectedTextAlignment(.right)
            document.updateSelectedTextFontSize(30)
        }

        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.selectedAnnotation?.rect.size, CGSize(width: 150, height: 44))
        XCTAssertEqual(document.selectedAnnotation?.fontSize, 30)
        XCTAssertEqual(document.selectedAnnotation?.textAlignment, .right)
        XCTAssertEqual(document.selectedAnnotation?.showsTextBackground, true)

        document.undo()
        XCTAssertEqual(document.annotation(withID: annotation.id)?.fontSize, 18)
        XCTAssertEqual(document.annotation(withID: annotation.id)?.textAlignment, .left)
        XCTAssertEqual(document.annotation(withID: annotation.id)?.showsTextBackground, false)

        document.undo()
        XCTAssertEqual(document.annotation(withID: annotation.id)?.rect.size, annotation.rect.size)

        document.undo()
        XCTAssertNil(document.selectedAnnotation)
        XCTAssertTrue(document.annotations.isEmpty)

        document.redo()
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.annotation(withID: annotation.id)?.text, "One")

        document.redo()
        XCTAssertEqual(document.annotation(withID: annotation.id)?.rect.size, CGSize(width: 150, height: 44))

        document.redo()
        XCTAssertEqual(document.annotation(withID: annotation.id)?.fontSize, 30)
        XCTAssertEqual(document.annotation(withID: annotation.id)?.textAlignment, .right)
        XCTAssertEqual(document.annotation(withID: annotation.id)?.showsTextBackground, true)
    }

    func testRenderedImageReflectsTextBackgroundAndAlignmentChanges() {
        let basePixels = Array(repeating: rgba(255, 255, 255), count: 240 * 120)
        let baseImage = makeImage(width: 240, height: 120, pixels: basePixels)

        let plainDocument = ScreenshotEditorDocument(image: baseImage)
        plainDocument.addAnnotation(.text(
            "TEST",
            at: CGPoint(x: 20, y: 20),
            color: .black,
            fontSize: 28,
            alignment: .left,
            showsBackground: false
        ))
        plainDocument.updateTextLayout(for: plainDocument.selectedAnnotation!.id, size: CGSize(width: 180, height: 50))
        let plainRendered = plainDocument.renderedImage()!

        let backgroundDocument = ScreenshotEditorDocument(image: baseImage)
        backgroundDocument.addAnnotation(.text(
            "TEST",
            at: CGPoint(x: 20, y: 20),
            color: .black,
            fontSize: 28,
            alignment: .left,
            showsBackground: true
        ))
        backgroundDocument.updateTextLayout(for: backgroundDocument.selectedAnnotation!.id, size: CGSize(width: 180, height: 50))
        let backgroundRendered = backgroundDocument.renderedImage()!

        XCTAssertGreaterThan(differingPixelCount(between: plainRendered, and: backgroundRendered), 500)

        let leftAlignedDocument = ScreenshotEditorDocument(image: baseImage)
        leftAlignedDocument.addAnnotation(.text(
            "TEST",
            at: CGPoint(x: 20, y: 20),
            color: .black,
            fontSize: 28,
            alignment: .left,
            showsBackground: false
        ))
        leftAlignedDocument.updateTextLayout(for: leftAlignedDocument.selectedAnnotation!.id, size: CGSize(width: 180, height: 50))
        let leftAlignedRendered = leftAlignedDocument.renderedImage()!

        let rightAlignedDocument = ScreenshotEditorDocument(image: baseImage)
        rightAlignedDocument.addAnnotation(.text(
            "TEST",
            at: CGPoint(x: 20, y: 20),
            color: .black,
            fontSize: 28,
            alignment: .right,
            showsBackground: false
        ))
        rightAlignedDocument.updateTextLayout(for: rightAlignedDocument.selectedAnnotation!.id, size: CGSize(width: 180, height: 50))
        let rightAlignedRendered = rightAlignedDocument.renderedImage()!

        XCTAssertGreaterThan(differingPixelCount(between: leftAlignedRendered, and: rightAlignedRendered), 100)
    }

    func testRenderedImagePreservesTextOrientationWhenSaving() {
        let basePixels = Array(repeating: rgba(255, 255, 255), count: 220 * 140)
        let baseImage = makeImage(width: 220, height: 140, pixels: basePixels)
        let document = ScreenshotEditorDocument(image: baseImage)
        let annotation = ScreenshotEditorAnnotation.text(
            "pqgy",
            at: CGPoint(x: 24, y: 28),
            color: .black,
            fontSize: 34,
            alignment: .left,
            showsBackground: true,
            backgroundColor: NSColor.systemYellow.withAlphaComponent(0.65)
        )
        document.addAnnotation(annotation)
        document.updateTextLayout(for: document.selectedAnnotation!.id, size: CGSize(width: 170, height: 60))

        let rendered = document.renderedImage()!
        let textBounds = document.selectedAnnotation!.rect.standardized.integral
        var weightedDarkPixelY = 0
        var darkPixelCount = 0

        for y in Int(textBounds.minY)..<Int(textBounds.maxY) {
            for x in Int(textBounds.minX)..<Int(textBounds.maxX) {
                let pixelValue = pixel(atX: x, y: y, in: rendered)
                let brightness = Int(pixelValue.r) + Int(pixelValue.g) + Int(pixelValue.b)
                if brightness < 180 {
                    weightedDarkPixelY += y
                    darkPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(darkPixelCount, 100)
        let darkPixelCenterY = Double(weightedDarkPixelY) / Double(darkPixelCount)
        XCTAssertGreaterThan(darkPixelCenterY, Double(textBounds.midY))
    }

    func testRenderedImageReflectsTextBackgroundColorChanges() {
        let basePixels = Array(repeating: rgba(255, 255, 255), count: 240 * 120)
        let baseImage = makeImage(width: 240, height: 120, pixels: basePixels)

        let darkBackgroundDocument = ScreenshotEditorDocument(image: baseImage)
        darkBackgroundDocument.addAnnotation(.text(
            "TEST",
            at: CGPoint(x: 20, y: 20),
            color: .white,
            fontSize: 28,
            alignment: .left,
            showsBackground: true,
            backgroundColor: NSColor.black.withAlphaComponent(0.55)
        ))
        darkBackgroundDocument.updateTextLayout(for: darkBackgroundDocument.selectedAnnotation!.id, size: CGSize(width: 180, height: 50))
        let darkRendered = darkBackgroundDocument.renderedImage()!

        let blueBackgroundDocument = ScreenshotEditorDocument(image: baseImage)
        blueBackgroundDocument.addAnnotation(.text(
            "TEST",
            at: CGPoint(x: 20, y: 20),
            color: .white,
            fontSize: 28,
            alignment: .left,
            showsBackground: true,
            backgroundColor: NSColor.systemBlue.withAlphaComponent(0.7)
        ))
        blueBackgroundDocument.updateTextLayout(for: blueBackgroundDocument.selectedAnnotation!.id, size: CGSize(width: 180, height: 50))
        let blueRendered = blueBackgroundDocument.renderedImage()!

        XCTAssertGreaterThan(differingPixelCount(between: darkRendered, and: blueRendered), 500)
    }

    func testTextToolClickCreatesInlineEditorThatAcceptsTyping() {
        let document = ScreenshotEditorDocument(image: makeImage(width: 120, height: 80, pixels: Array(repeating: rgba(255, 255, 255), count: 120 * 80)))
        let canvas = ScreenshotEditorCanvasView(document: document)
        canvas.tool = .text
        canvas.activeColor = .systemRed
        canvas.activeTextFontSize = 20
        canvas.activeTextAlignment = .left
        canvas.activeTextShowsBackground = true

        let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        canvas.frame = CGRect(origin: .zero, size: CGSize(width: 120, height: 80))
        hostView.addSubview(canvas)

        let window = NSWindow(
            contentRect: hostView.bounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)

        let clickLocation = CGPoint(x: 24, y: 28)
        let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: window.convertPoint(toScreen: clickLocation),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: window.convertPoint(toScreen: clickLocation),
            modifierFlags: [],
            timestamp: 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )!

        canvas.mouseDown(with: mouseDown)
        canvas.mouseUp(with: mouseUp)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let textView = findSubview(in: canvas) { $0 as? NSTextView }
        XCTAssertNotNil(textView)
        XCTAssertTrue(textView?.isEditable == true)
        XCTAssertTrue(window.firstResponder === textView)
        XCTAssertEqual(document.selectedAnnotation?.kind, .text)

        textView?.allowsUndo = false
        sendKeyText("Hello", to: textView!)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(document.selectedAnnotation?.text, "Hello")
    }

}

final class HotkeyManagerTests: XCTestCase {
    func testDefaultCaptureHotkeyMatchesExpectedShortcut() {
        let descriptor = HotkeyManager.defaultCaptureHotkey

        XCTAssertEqual(descriptor.id, 1)
        XCTAssertEqual(descriptor.keyCode, 19)
        XCTAssertEqual(descriptor.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testDevelopmentEnvironmentDiagnosticsFlagsDerivedDataAndAdHocSigningAsUnstable() {
        let diagnostics = DevelopmentEnvironmentDiagnostics(
            bundlePath: "/Users/test/Library/Developer/Xcode/DerivedData/scrshot/Build/Products/Debug/scrshot.app",
            bundleIdentifier: "io.github.Warrfie.scrshot",
            teamIdentifier: "not set"
        )

        XCTAssertTrue(diagnostics.isRunningFromDerivedData)
        XCTAssertTrue(diagnostics.isAdHocSigned)
        XCTAssertTrue(diagnostics.likelyCausesTCCPermissionMismatch)
    }

    func testDevelopmentEnvironmentDiagnosticsTreatsStableSignedAppAsSafe() {
        let diagnostics = DevelopmentEnvironmentDiagnostics(
            bundlePath: "/Users/test/Applications/scrshot-dev.app",
            bundleIdentifier: "io.github.Warrfie.scrshot",
            teamIdentifier: "7G4FAJX848"
        )

        XCTAssertFalse(diagnostics.isRunningFromDerivedData)
        XCTAssertFalse(diagnostics.isAdHocSigned)
        XCTAssertFalse(diagnostics.likelyCausesTCCPermissionMismatch)
    }

    func testDevelopmentAppRelaunchCoordinatorRequestsRelaunchForUnstableXcodeRun() {
        let diagnostics = DevelopmentEnvironmentDiagnostics(
            bundlePath: "/Users/test/Library/Developer/Xcode/DerivedData/scrshot/Build/Products/Debug/scrshot.app",
            bundleIdentifier: "io.github.Warrfie.scrshot",
            teamIdentifier: "nil"
        )
        let coordinator = DevelopmentAppRelaunchCoordinator(environment: [:], fileManager: .default)

        XCTAssertTrue(coordinator.shouldRelaunch(diagnostics: diagnostics))
    }

    func testDevelopmentAppRelaunchCoordinatorSkipsRelaunchForTestsAndStableApps() {
        let stableDiagnostics = DevelopmentEnvironmentDiagnostics(
            bundlePath: "/Users/test/Applications/scrshot-dev.app",
            bundleIdentifier: "io.github.Warrfie.scrshot",
            teamIdentifier: "7G4FAJX848"
        )
        let unstableDiagnostics = DevelopmentEnvironmentDiagnostics(
            bundlePath: "/Users/test/Library/Developer/Xcode/DerivedData/scrshot/Build/Products/Debug/scrshot.app",
            bundleIdentifier: "io.github.Warrfie.scrshot",
            teamIdentifier: "nil"
        )

        let testCoordinator = DevelopmentAppRelaunchCoordinator(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
            fileManager: .default
        )
        let relaunchedCoordinator = DevelopmentAppRelaunchCoordinator(
            environment: [DevelopmentAppRelaunchCoordinator.relaunchedEnvironmentKey: "1"],
            fileManager: .default
        )

        XCTAssertFalse(testCoordinator.shouldRelaunch(diagnostics: unstableDiagnostics))
        XCTAssertFalse(relaunchedCoordinator.shouldRelaunch(diagnostics: unstableDiagnostics))
        XCTAssertFalse(testCoordinator.shouldRelaunch(diagnostics: stableDiagnostics))
    }

    func testDevelopmentAppRelaunchCoordinatorResolvesExecutableFromBundleInfo() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scrshot-dev-app-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("scrshot-dev.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleExecutable": "scrshot",
            "CFBundleIdentifier": "io.github.Warrfie.scrshot",
            "CFBundlePackageType": "APPL"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let coordinator = DevelopmentAppRelaunchCoordinator(environment: [:], fileManager: .default)
        let executableURL = try coordinator.executableURL(forAppAt: appURL)

        XCTAssertEqual(executableURL.path, macOSURL.appendingPathComponent("scrshot").path)
    }

    func testDevelopmentAppRelaunchCoordinatorBuildsLaunchServicesArgumentsForStableApp() {
        let appURL = URL(fileURLWithPath: "/Users/example/Applications/scrshot-dev.app", isDirectory: true)
        let arguments = DevelopmentAppRelaunchCoordinator.launchArguments(
            forAppAt: appURL,
            environment: [DevelopmentAppRelaunchCoordinator.relaunchedEnvironmentKey: "1"]
        )

        XCTAssertEqual(
            arguments,
            ["-na", appURL.path, "--env", "\(DevelopmentAppRelaunchCoordinator.relaunchedEnvironmentKey)=1"]
        )
    }

    func testAppInstanceCoordinatorDetectsAnotherRunningInstance() {
        let coordinator = AppInstanceCoordinator(
            bundleIdentifier: "io.github.Warrfie.scrshot",
            currentProcessIdentifier: 100,
            runningApplicationsProvider: { _ in
                [
                    .init(processIdentifier: 100),
                    .init(processIdentifier: 222)
                ]
            }
        )

        XCTAssertEqual(coordinator.existingInstanceProcessIdentifier(), 222)
    }

    func testAppInstanceCoordinatorIgnoresCurrentProcessWhenSingleInstance() {
        let coordinator = AppInstanceCoordinator(
            bundleIdentifier: "io.github.Warrfie.scrshot",
            currentProcessIdentifier: 100,
            runningApplicationsProvider: { _ in
                [.init(processIdentifier: 100)]
            }
        )

        XCTAssertNil(coordinator.existingInstanceProcessIdentifier())
    }

    func testPermissionPreflightPolicySkipsLaunchPreflightInTests() {
        let policy = PermissionPreflightPolicy(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        )

        XCTAssertFalse(policy.shouldRunOnLaunch)
    }

    func testPermissionPreflightPolicyRespectsManualSkipFlag() {
        let policy = PermissionPreflightPolicy(
            environment: [PermissionPreflightPolicy.skipEnvironmentKey: "true"]
        )

        XCTAssertFalse(policy.shouldRunOnLaunch)
    }

    func testPermissionStatusSnapshotSummariesReflectCurrentAccessState() {
        let deniedSnapshot = PermissionStatusSnapshot(
            screenCaptureGranted: false,
            microphoneStatus: .notDetermined
        )
        XCTAssertEqual(deniedSnapshot.screenCaptureSummary, "Not Allowed")
        XCTAssertEqual(deniedSnapshot.microphoneSummary, "Not Requested")

        let grantedSnapshot = PermissionStatusSnapshot(
            screenCaptureGranted: true,
            microphoneStatus: .authorized
        )
        XCTAssertEqual(grantedSnapshot.screenCaptureSummary, "Allowed")
        XCTAssertEqual(grantedSnapshot.microphoneSummary, "Allowed")
    }
}

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testPreferencesPersistHotkeyThemeAndSaveDirectory() {
        let suiteName = "scrshot-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = AppPreferences(defaults: defaults)

        let customDirectory = URL(fileURLWithPath: "/tmp/scrshot-custom-save", isDirectory: true)
        let customHotkey = HotkeyManager.HotkeyDescriptor(id: 1, keyCode: 24, modifiers: UInt32(cmdKey | optionKey))

        preferences.captureHotkey = customHotkey
        preferences.theme = .dark
        preferences.saveDirectoryURL = customDirectory
        preferences.launchAtLogin = true
        preferences.exportBehavior = .saveOnly
        preferences.fileNamePrefix = "team-shot"
        preferences.timestampTemplate = "yyyyMMdd-HHmm"
        preferences.revealSavedFile = true
        preferences.recordingAudioSource = .systemAudioAndMicrophone
        preferences.recordingFileFormat = .mp4
        preferences.captureSound = .hero

        let reloaded = AppPreferences(defaults: defaults)

        XCTAssertEqual(reloaded.captureHotkey.id, customHotkey.id)
        XCTAssertEqual(reloaded.captureHotkey.keyCode, customHotkey.keyCode)
        XCTAssertEqual(reloaded.captureHotkey.modifiers, customHotkey.modifiers)
        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertEqual(reloaded.saveDirectoryURL.path, customDirectory.path)
        XCTAssertEqual(reloaded.launchAtLogin, true)
        XCTAssertEqual(reloaded.exportBehavior, .saveOnly)
        XCTAssertEqual(reloaded.fileNamePrefix, "team-shot")
        XCTAssertEqual(reloaded.timestampTemplate, "yyyyMMdd-HHmm")
        XCTAssertEqual(reloaded.revealSavedFile, true)
        XCTAssertEqual(reloaded.recordingAudioSource, .systemAudioAndMicrophone)
        XCTAssertEqual(reloaded.recordingFileFormat, .mp4)
        XCTAssertEqual(reloaded.captureSound, .hero)
    }

    func testPreferencesDefaultSaveDirectoryEndsWithScreenshots() {
        let suiteName = "scrshot-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.saveDirectoryURL.path.hasSuffix("/Documents/Screenshots"))
    }

    func testPreferencesFallbackToDefaultsAfterResetAndInvalidThemeValue() {
        let suiteName = "scrshot-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("bogus-theme", forKey: AppPreferences.Keys.theme)
        defaults.set(24, forKey: AppPreferences.Keys.hotkeyKeyCode)
        defaults.set(UInt32(cmdKey | optionKey), forKey: AppPreferences.Keys.hotkeyModifiers)
        defaults.set("/tmp/custom-folder", forKey: AppPreferences.Keys.saveDirectoryPath)
        defaults.set(true, forKey: AppPreferences.Keys.launchAtLogin)
        defaults.set(AppPreferences.ExportBehavior.saveOnly.rawValue, forKey: AppPreferences.Keys.exportBehavior)
        defaults.set("team-shot", forKey: AppPreferences.Keys.fileNamePrefix)
        defaults.set("yyyyMMdd", forKey: AppPreferences.Keys.timestampTemplate)
        defaults.set(true, forKey: AppPreferences.Keys.revealSavedFile)
        defaults.set("bogus-audio-source", forKey: AppPreferences.Keys.recordingAudioSource)
        defaults.set("bogus-recording-format", forKey: AppPreferences.Keys.recordingFileFormat)

        defaults.removePersistentDomain(forName: suiteName)
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.theme, .system)
        XCTAssertEqual(preferences.captureHotkey.keyCode, HotkeyManager.defaultCaptureHotkey.keyCode)
        XCTAssertEqual(preferences.captureHotkey.modifiers, HotkeyManager.defaultCaptureHotkey.modifiers)
        XCTAssertTrue(preferences.saveDirectoryURL.path.hasSuffix("/Documents/Screenshots"))
        XCTAssertEqual(preferences.launchAtLogin, false)
        XCTAssertEqual(preferences.exportBehavior, .copyAndSave)
        XCTAssertEqual(preferences.fileNamePrefix, "screenshot")
        XCTAssertEqual(preferences.timestampTemplate, "yyyy-MM-dd_HH-mm-ss")
        XCTAssertEqual(preferences.revealSavedFile, false)
        XCTAssertEqual(preferences.playsCaptureSound, true)
        XCTAssertEqual(preferences.captureSound, .grab)
        XCTAssertEqual(preferences.recordingAudioSource, .systemAudio)
        XCTAssertEqual(preferences.recordingFileFormat, .mov)
    }

    func testResetToDefaultsClearsCustomExportSettings() {
        let suiteName = "scrshot-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = AppPreferences(defaults: defaults)

        preferences.launchAtLogin = true
        preferences.exportBehavior = .copyOnly
        preferences.fileNamePrefix = " custom:name "
        preferences.timestampTemplate = "yyyyMMdd"
        preferences.revealSavedFile = true
        preferences.playsCaptureSound = false
        preferences.captureSound = .submarine
        preferences.recordingAudioSource = .microphoneOnly
        preferences.recordingFileFormat = .mp4
        preferences.resetToDefaults()

        XCTAssertEqual(preferences.launchAtLogin, false)
        XCTAssertEqual(preferences.exportBehavior, .copyAndSave)
        XCTAssertEqual(preferences.fileNamePrefix, "screenshot")
        XCTAssertEqual(preferences.timestampTemplate, "yyyy-MM-dd_HH-mm-ss")
        XCTAssertEqual(preferences.revealSavedFile, false)
        XCTAssertEqual(preferences.playsCaptureSound, true)
        XCTAssertEqual(preferences.captureSound, .grab)
        XCTAssertEqual(preferences.recordingAudioSource, .systemAudio)
        XCTAssertEqual(preferences.recordingFileFormat, .mov)
    }
}

@MainActor
final class AppTerminationStateTrackerTests: XCTestCase {
    func testMarkLaunchStartedReportsPreviousCrashWhenLastRunWasUnclean() {
        let suiteName = "scrshot-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: AppTerminationStateTracker.Keys.lastRunEndedCleanly)
        let tracker = AppTerminationStateTracker(defaults: defaults)

        let didPreviousRunCrash = MainActor.assumeIsolated {
            tracker.markLaunchStarted(now: Date(timeIntervalSince1970: 123))
        }

        XCTAssertTrue(didPreviousRunCrash)
        XCTAssertEqual(defaults.object(forKey: AppTerminationStateTracker.Keys.lastRunEndedCleanly) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: AppTerminationStateTracker.Keys.lastLaunchTimestamp) as? TimeInterval, 123)
    }

    func testMarkTerminatedCleanlyClearsCrashFlag() {
        let suiteName = "scrshot-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tracker = AppTerminationStateTracker(defaults: defaults)

        MainActor.assumeIsolated {
            _ = tracker.markLaunchStarted()
            tracker.markTerminatedCleanly()
        }

        XCTAssertEqual(defaults.object(forKey: AppTerminationStateTracker.Keys.lastRunEndedCleanly) as? Bool, true)
    }
}

@MainActor
final class CaptureSoundPlayerTests: XCTestCase {
    func testPlayCaptureSoundIfEnabledUsesNamedSoundWhenAvailable() {
        let expectations = expectation(description: "named sound played")
        var requestedSoundName: NSSound.Name?
        let sound = TestSound {
            expectations.fulfill()
        }
        let player = CaptureSoundPlayer(
            namedSoundProvider: {
                requestedSoundName = $0
                return sound
            },
            beepPlayer: XCTFailingClosure("beep should not be used when named sound is available")
        )
        let preferences = makePreferencesForSoundTests()
        preferences.playsCaptureSound = true
        preferences.captureSound = .hero

        let played = MainActor.assumeIsolated {
            player.playCaptureSoundIfEnabled(preferences: preferences)
        }

        XCTAssertTrue(played)
        XCTAssertEqual(requestedSoundName, "Hero")
        wait(for: [expectations], timeout: 0.1)
    }

    func testPlayCaptureSoundIfEnabledFallsBackToBeepForExplicitBeepSelection() {
        let expectations = expectation(description: "beep played")
        let player = CaptureSoundPlayer(
            namedSoundProvider: { _ in XCTFail("named sound should not be requested for system beep"); return nil },
            beepPlayer: {
                expectations.fulfill()
            }
        )
        let preferences = makePreferencesForSoundTests()
        preferences.playsCaptureSound = true
        preferences.captureSound = .beep

        let played = MainActor.assumeIsolated {
            player.playCaptureSoundIfEnabled(preferences: preferences)
        }

        XCTAssertTrue(played)
        wait(for: [expectations], timeout: 0.1)
    }

    func testPlayCaptureSoundIfEnabledFallsBackToBeepWhenNamedSoundMissing() {
        let expectations = expectation(description: "beep played")
        var requestedSoundName: NSSound.Name?
        let player = CaptureSoundPlayer(
            namedSoundProvider: {
                requestedSoundName = $0
                return nil
            },
            beepPlayer: {
                expectations.fulfill()
            }
        )
        let preferences = makePreferencesForSoundTests()
        preferences.playsCaptureSound = true
        preferences.captureSound = .glass

        let played = MainActor.assumeIsolated {
            player.playCaptureSoundIfEnabled(preferences: preferences)
        }

        XCTAssertTrue(played)
        XCTAssertEqual(requestedSoundName, "Glass")
        wait(for: [expectations], timeout: 0.1)
    }

    func testPlayCaptureSoundIfEnabledSkipsPlaybackWhenDisabled() {
        let player = CaptureSoundPlayer(
            namedSoundProvider: { _ in XCTFail("named sound should not be requested"); return nil },
            beepPlayer: XCTFailingClosure("beep should not be used when sound is disabled")
        )
        let preferences = makePreferencesForSoundTests()
        preferences.playsCaptureSound = false

        let played = MainActor.assumeIsolated {
            player.playCaptureSoundIfEnabled(preferences: preferences)
        }

        XCTAssertFalse(played)
    }
}

final class ImageSaverTests: XCTestCase {
    func testSaveWritesPNGIntoRequestedDirectory() throws {
        let saver = ImageSaver()
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scrshot-image-saver-\(UUID().uuidString)", isDirectory: true)
        let outputURL = try saver.save(
            image: makeImage(width: 2, height: 2, pixels: Array(repeating: rgba(10, 20, 30), count: 4)),
            directory: rootDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(outputURL.deletingLastPathComponent().path, rootDirectory.path)
        XCTAssertEqual(outputURL.pathExtension.lowercased(), "png")

        let data = try Data(contentsOf: outputURL)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testSaveUsesCustomPrefixAndTimestampTemplate() throws {
        let saver = ImageSaver()
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scrshot-image-saver-custom-\(UUID().uuidString)", isDirectory: true)
        let fixedDate = ISO8601DateFormatter().date(from: "2026-03-26T15:04:05Z")!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let outputURL = try saver.save(
            image: makeImage(width: 2, height: 2, pixels: Array(repeating: rgba(20, 30, 40), count: 4)),
            options: ImageSaver.Options(
                directory: rootDirectory,
                fileNamePrefix: "release:shot",
                timestampTemplate: "yyyyMMdd-HHmmss"
            ),
            date: fixedDate
        )

        XCTAssertEqual(
            outputURL.lastPathComponent,
            "release-shot_\(formatter.string(from: fixedDate)).png"
        )
    }

    @MainActor
    func testSavePreservesRenderedLineOrientationInFinalPNG() throws {
        let document = ScreenshotEditorDocument(image: makeImage(width: 24, height: 24, pixels: Array(repeating: rgba(255, 255, 255), count: 576)))
        document.addAnnotation(.line(
            from: CGPoint(x: 3, y: 3),
            to: CGPoint(x: 20, y: 3),
            color: .black
        ))
        let rendered = try XCTUnwrap(document.renderedImage())

        let saver = ImageSaver()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scrshot-image-saver-line-\(UUID().uuidString)", isDirectory: true)
        let outputURL = try saver.save(image: rendered, directory: directory)
        let savedImage = try XCTUnwrap(loadCGImage(from: outputURL))

        XCTAssertNotEqual(pixel(atX: 12, y: 3, in: savedImage), rgba(255, 255, 255))
        XCTAssertEqual(pixel(atX: 12, y: 20, in: savedImage), rgba(255, 255, 255))
    }

    func testSavePreservesBaseImageOrientationInFinalPNG() throws {
        let source = makeImage(
            width: 4,
            height: 4,
            pixels: [
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(255, 0, 0), rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0),
                rgba(0, 0, 255), rgba(0, 0, 255), rgba(255, 255, 0), rgba(255, 255, 0),
            ]
        )

        let saver = ImageSaver()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scrshot-image-saver-base-\(UUID().uuidString)", isDirectory: true)
        let outputURL = try saver.save(image: source, directory: directory)
        let savedImage = try XCTUnwrap(loadCGImage(from: outputURL))

        XCTAssertEqual(pixel(atX: 0, y: 0, in: savedImage), rgba(255, 0, 0))
        XCTAssertEqual(pixel(atX: 3, y: 0, in: savedImage), rgba(0, 255, 0))
        XCTAssertEqual(pixel(atX: 0, y: 3, in: savedImage), rgba(0, 0, 255))
        XCTAssertEqual(pixel(atX: 3, y: 3, in: savedImage), rgba(255, 255, 0))
    }
}

private func makeImage(width: Int, height: Int, pixels: [RGBA]) -> CGImage {
    precondition(pixels.count == width * height)
    let bytes = pixels.flatMap { [$0.r, $0.g, $0.b, $0.a] }
    let data = Data(bytes)
    let provider = CGDataProvider(data: data as CFData)!
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func loadCGImage(from url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func pixel(atX x: Int, y: Int, in image: CGImage) -> RGBA {
    let data = image.dataProvider!.data!
    let bytes = CFDataGetBytePtr(data)!
    let offset = y * image.bytesPerRow + x * 4
    return RGBA(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
}

private func findSubview<T>(in view: NSView, matcher: (NSView) -> T?) -> T? {
    if let match = matcher(view) {
        return match
    }

    for subview in view.subviews {
        if let match = findSubview(in: subview, matcher: matcher) {
            return match
        }
    }

    return nil
}

@MainActor
private func sendKeyText(_ text: String, to textView: NSTextView) {
    for scalar in text.unicodeScalars {
        let character = String(scalar)
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: textView.window?.windowNumber ?? 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        ) else {
            XCTFail("Failed to create key event for \(character)")
            return
        }
        textView.keyDown(with: event)
    }
}

private func differingPixelCount(between lhs: CGImage, and rhs: CGImage) -> Int {
    precondition(lhs.width == rhs.width && lhs.height == rhs.height)
    var differingPixels = 0
    for y in 0..<lhs.height {
        for x in 0..<lhs.width {
            if pixel(atX: x, y: y, in: lhs) != pixel(atX: x, y: y, in: rhs) {
                differingPixels += 1
            }
        }
    }
    return differingPixels
}

private func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> RGBA {
    RGBA(r, g, b, a)
}

@MainActor
private func makePreferencesForSoundTests() -> AppPreferences {
    let suiteName = "scrshot-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return AppPreferences(defaults: defaults)
}

private final class TestSound: SoundPlayback, @unchecked Sendable {
    private let onPlay: () -> Void

    init(onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
    }

    func play() -> Bool {
        onPlay()
        return true
    }
}

private func XCTFailingClosure(_ message: String) -> () -> Void {
    {
        XCTFail(message)
    }
}

private struct RGBA: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
