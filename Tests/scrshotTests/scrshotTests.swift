import XCTest
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

    func testRenderedImageIncludesRedactAnnotation() {
        let basePixels = Array(repeating: rgba(230, 230, 230), count: 40 * 40)
        let document = ScreenshotEditorDocument(image: makeImage(width: 40, height: 40, pixels: basePixels))
        document.addAnnotation(.obscure(CGRect(x: 8, y: 8, width: 16, height: 16), style: .redact))

        let rendered = document.renderedImage()

        XCTAssertEqual(pixel(atX: 16, y: 16, in: rendered!), rgba(0, 0, 0))
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
}

final class HotkeyManagerTests: XCTestCase {
    func testDefaultCaptureHotkeyMatchesExpectedShortcut() {
        let descriptor = HotkeyManager.defaultCaptureHotkey

        XCTAssertEqual(descriptor.id, 1)
        XCTAssertEqual(descriptor.keyCode, 19)
        XCTAssertEqual(descriptor.modifiers, UInt32(cmdKey | shiftKey))
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
        preferences.recordingAudioSource = .microphoneOnly
        preferences.recordingFileFormat = .mp4
        preferences.resetToDefaults()

        XCTAssertEqual(preferences.launchAtLogin, false)
        XCTAssertEqual(preferences.exportBehavior, .copyAndSave)
        XCTAssertEqual(preferences.fileNamePrefix, "screenshot")
        XCTAssertEqual(preferences.timestampTemplate, "yyyy-MM-dd_HH-mm-ss")
        XCTAssertEqual(preferences.revealSavedFile, false)
        XCTAssertEqual(preferences.recordingAudioSource, .systemAudio)
        XCTAssertEqual(preferences.recordingFileFormat, .mov)
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

private func pixel(atX x: Int, y: Int, in image: CGImage) -> RGBA {
    let data = image.dataProvider!.data!
    let bytes = CFDataGetBytePtr(data)!
    let offset = y * image.bytesPerRow + x * 4
    return RGBA(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
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
