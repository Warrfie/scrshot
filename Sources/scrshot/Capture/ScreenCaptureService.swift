import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ScreenCapturePermissionController {
    static let shared = ScreenCapturePermissionController()

    private let preflightAccess: () -> Bool
    private let requestAccess: () -> Bool
    private let activateApp: () -> Void
    private var hasRequestedThisLaunch = false

    init(
        preflightAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        self.preflightAccess = preflightAccess
        self.requestAccess = requestAccess
        self.activateApp = activateApp
    }

    var hasAccess: Bool {
        preflightAccess()
    }

    var hasRequestedSystemPrompt: Bool {
        hasRequestedThisLaunch
    }

    @discardableResult
    func requestAccessIfNeeded() -> Bool {
        guard !hasAccess else { return true }
        guard !hasRequestedSystemPrompt else { return false }
        activateApp()
        hasRequestedThisLaunch = true
        return requestAccess()
    }
}

final class MicrophonePermissionController {
    static let shared = MicrophonePermissionController()

    private let authorizationStatusProvider: () -> AVAuthorizationStatus
    private let requestAccess: () async -> Bool
    private let activateApp: () -> Void
    private var hasRequestedThisLaunch = false

    init(
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        requestAccess: @escaping () async -> Bool = {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        },
        activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider
        self.requestAccess = requestAccess
        self.activateApp = activateApp
    }

    var authorizationStatus: AVAuthorizationStatus {
        authorizationStatusProvider()
    }

    var hasAccess: Bool {
        authorizationStatus == .authorized
    }

    var hasRequestedSystemPrompt: Bool {
        hasRequestedThisLaunch
    }

    @discardableResult
    func requestAccessIfNeeded() async -> Bool {
        guard !hasAccess else { return true }
        guard authorizationStatus == .notDetermined else { return false }
        guard !hasRequestedSystemPrompt else { return false }
        await MainActor.run {
            activateApp()
        }
        hasRequestedThisLaunch = true
        return await requestAccess()
    }
}

final class ScreenCaptureService {
    private let permissionController: ScreenCapturePermissionController

    init(permissionController: ScreenCapturePermissionController = .shared) {
        self.permissionController = permissionController
    }

    struct CapturedScreen {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let image: CGImage
        let scaleX: CGFloat
        let scaleY: CGFloat
    }
    enum CaptureError: LocalizedError {
        case screenRecordingPermissionDenied
        case captureFailed
        case selectionOutsideVisibleScreens
        case failedToCreateContext
        var errorDescription: String? {
            switch self {
            case .screenRecordingPermissionDenied:
                return "Screen Recording permission is required."
            case .captureFailed:
                return "Unable to capture the current displays."
            case .selectionOutsideVisibleScreens:
                return "The selected area does not intersect any visible display."
            case .failedToCreateContext:
                return "Unable to create an image context."
            }
        }
    }

    private func log(_ message: String) {
        AppLogger.shared.info(.screenCaptureService, message)
    }

    private func debugLog(_ message: String) {
        AppLogger.shared.debug(.screenCaptureService, message)
    }

    func captureCurrentDisplay() throws -> CapturedScreen {
        let hasPermission = permissionController.hasAccess
        debugLog("captureCurrentDisplay start; preflight=\(hasPermission)")

        guard hasPermission else {
            let requestResult = permissionController.requestAccessIfNeeded()
            log("preflight denied; requestResult=\(requestResult) alreadyPrompted=\(permissionController.hasRequestedSystemPrompt)")
            throw CaptureError.screenRecordingPermissionDenied
        }

        if let capturedDisplay = currentCapturedScreenFromSystem() {
            debugLog("captureCurrentDisplay success displayID=\(capturedDisplay.displayID)")
            return capturedDisplay
        }

        log("captureCurrentDisplay failed; preflight ok but no image")
        throw CaptureError.captureFailed
    }
    func compositeImage(from screens: [CapturedScreen]) throws -> CGImage {
        let union = screens.map(\.frame).reduce(CGRect.null, { $0.union($1) })
        return try crop(selection: union, from: screens)
    }

    func crop(selection: CGRect, from screens: [CapturedScreen]) throws -> CGImage {
        let normalizedSelection = selection.standardized.integral
        let intersectingScreens = screens.filter { $0.frame.intersects(normalizedSelection) }
        guard !intersectingScreens.isEmpty else {
            throw CaptureError.selectionOutsideVisibleScreens
        }
        let targetScale = intersectingScreens.reduce(CGFloat(1)) { partialResult, screen in
            max(partialResult, max(screen.scaleX, screen.scaleY))
        }
        let canvasWidth = Int(ceil(normalizedSelection.width * targetScale))
        let canvasHeight = Int(ceil(normalizedSelection.height * targetScale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: canvasWidth,
                height: canvasHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CaptureError.failedToCreateContext
        }
        context.interpolationQuality = .high
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        for screen in intersectingScreens {
            let intersection = screen.frame.intersection(normalizedSelection)
            guard !intersection.isNull else { continue }
            let localRect = CGRect(
                x: intersection.minX - screen.frame.minX,
                y: intersection.minY - screen.frame.minY,
                width: intersection.width,
                height: intersection.height
            )
            var cropRect = CGRect(
                x: floor(localRect.minX * screen.scaleX),
                y: floor((screen.frame.height - localRect.maxY) * screen.scaleY),
                width: ceil(localRect.width * screen.scaleX),
                height: ceil(localRect.height * screen.scaleY)
            ).integral
            let sourceBounds = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(screen.image.width),
                height: CGFloat(screen.image.height)
            )
            cropRect = cropRect.intersection(sourceBounds)
            guard !cropRect.isNull, let croppedImage = screen.image.cropping(to: cropRect) else {
                continue
            }
            let destinationRect = CGRect(
                x: (intersection.minX - normalizedSelection.minX) * targetScale,
                y: (intersection.minY - normalizedSelection.minY) * targetScale,
                width: intersection.width * targetScale,
                height: intersection.height * targetScale
            )
            context.draw(croppedImage, in: destinationRect)
        }
        guard let image = context.makeImage() else {
            throw CaptureError.captureFailed
        }
        return image
    }
    private func currentCapturedScreenFromSystem() -> CapturedScreen? {
        if let selection = selectedScreenForCapture() {
            debugLog("selected screen frame=\(NSStringFromRect(selection.screen.frame)) displayIndex=\(selection.displayIndex) displayID=\(selection.screen.displayID.map(String.init) ?? "nil")")
        } else {
            debugLog("selected screen unavailable")
        }

        if #available(macOS 14.0, *), let capturedScreen = captureWithScreenCaptureKitDisplayFilter() {
            debugLog("using ScreenCaptureKit display-filter backend image=\(capturedScreen.image.width)x\(capturedScreen.image.height)")
            return capturedScreen
        }

        if #available(macOS 15.2, *), let capturedScreen = captureWithScreenCaptureKitRect() {
            debugLog("using ScreenCaptureKit rect backend image=\(capturedScreen.image.width)x\(capturedScreen.image.height)")
            return capturedScreen
        }

        log("ScreenCaptureKit backends returned nil")
        return nil
    }

    @available(macOS 15.2, *)
    private func captureWithScreenCaptureKitRect() -> CapturedScreen? {
        guard let selection = selectedScreenForCapture(),
              let displayID = selection.screen.displayID else {
            debugLog("ScreenCaptureKit rect backend: no selected screen")
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var imageResult: Result<CGImage, Error>?
        debugLog("ScreenCaptureKit rect backend: capturing rect \(NSStringFromRect(selection.screen.frame))")
        SCScreenshotManager.captureImage(in: selection.screen.frame) { image, error in
            if let image {
                imageResult = .success(image)
            } else {
                imageResult = .failure(error ?? CaptureError.captureFailed)
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard case let .success(image)? = imageResult else {
            if case let .failure(error)? = imageResult {
                log("ScreenCaptureKit rect capture failed: \(error.localizedDescription)")
            }
            return nil
        }

        let frame = selection.screen.frame
        debugLog("ScreenCaptureKit rect backend success image=\(image.width)x\(image.height)")
        return CapturedScreen(
            displayID: displayID,
            frame: frame,
            image: image,
            scaleX: CGFloat(image.width) / frame.width,
            scaleY: CGFloat(image.height) / frame.height
        )
    }

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKitDisplayFilter() -> CapturedScreen? {
        guard let selection = selectedScreenForCapture(),
              let displayID = selection.screen.displayID else {
            debugLog("ScreenCaptureKit display-filter backend: no selected screen")
            return nil
        }

        let shareableContentSemaphore = DispatchSemaphore(value: 0)
        var shareableContentResult: Result<SCShareableContent, Error>?
        debugLog("ScreenCaptureKit display-filter backend: requesting shareable content")
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            if let content {
                shareableContentResult = .success(content)
            } else {
                shareableContentResult = .failure(error ?? CaptureError.captureFailed)
            }
            shareableContentSemaphore.signal()
        }
        shareableContentSemaphore.wait()

        guard case let .success(shareableContent)? = shareableContentResult else {
            if case let .failure(error)? = shareableContentResult {
                log("ScreenCaptureKit shareable content failed: \(error.localizedDescription)")
            }
            return nil
        }

        guard let scDisplay = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            log("ScreenCaptureKit display-filter backend: no matching SCDisplay for displayID=\(displayID)")
            return nil
        }

        let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scaleFactor = selection.screen.backingScaleFactor
        configuration.width = max(1, Int(scDisplay.frame.width * scaleFactor))
        configuration.height = max(1, Int(scDisplay.frame.height * scaleFactor))
        debugLog("ScreenCaptureKit display-filter backend: config \(configuration.width)x\(configuration.height)")

        let imageSemaphore = DispatchSemaphore(value: 0)
        var imageResult: Result<CGImage, Error>?
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            if let image {
                imageResult = .success(image)
            } else {
                imageResult = .failure(error ?? CaptureError.captureFailed)
            }
            imageSemaphore.signal()
        }
        imageSemaphore.wait()

        guard case let .success(image)? = imageResult else {
            if case let .failure(error)? = imageResult {
                log("ScreenCaptureKit display-filter capture failed: \(error.localizedDescription)")
            }
            return nil
        }

        let frame = selection.screen.frame
        debugLog("ScreenCaptureKit display-filter backend success image=\(image.width)x\(image.height)")
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        return CapturedScreen(
            displayID: displayID,
            frame: frame,
            image: image,
            scaleX: scaleX,
            scaleY: scaleY
        )
    }

    private func selectedScreenForCapture() -> (screen: NSScreen, displayIndex: Int)? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? screens[0]
        guard let index = screens.firstIndex(where: { $0 === screen }) else {
            return (screen, 1)
        }
        return (screen, index + 1)
    }

}
