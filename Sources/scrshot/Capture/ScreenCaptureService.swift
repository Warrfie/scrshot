import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

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
    private(set) var lastCaptureURL: URL?
    private let permissionController: ScreenCapturePermissionController
    private var cacheContainerName: String {
        Bundle.main.bundleIdentifier ?? "scrshot"
    }

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

    private func saveDebugImage(_ image: CGImage, named name: String) {
#if DEBUG
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let debugDirectory = cachesDirectory
            .appendingPathComponent(cacheContainerName, isDirectory: true)
            .appendingPathComponent("DebugCaptures", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
            let fileURL = debugDirectory.appendingPathComponent(name).appendingPathExtension("png")
            guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            if CGImageDestinationFinalize(destination) {
                debugLog("debug image saved at \(fileURL.path)")
            }
        } catch {
            debugLog("failed saving debug image \(name): \(error.localizedDescription)")
        }
#endif
    }

    private func logVisibleWindowDiagnostics() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostName = frontmostApp?.localizedName ?? "nil"
        let frontmostBundleID = frontmostApp?.bundleIdentifier ?? "nil"
        debugLog("frontmost app name=\(frontmostName) bundleID=\(frontmostBundleID)")

        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            debugLog("CGWindowListCopyWindowInfo returned nil")
            return
        }

        let interestingWindows = windowInfo.prefix(12).map { info -> String in
            let owner = info[kCGWindowOwnerName as String] as? String ?? "unknown-owner"
            let title = info[kCGWindowName as String] as? String ?? "untitled"
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            return "\(owner)::\(title) layer=\(layer) bounds=\(bounds)"
        }.joined(separator: " | ")
        debugLog("visible CG windows count=\(windowInfo.count) [\(interestingWindows)]")
    }

    private func logImageDiagnostics(_ image: CGImage, label: String) {
        guard let providerData = image.dataProvider?.data,
              let data = CFDataGetBytePtr(providerData) else {
            debugLog("\(label) image diagnostics unavailable; no provider data")
            return
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let samplePoints = [
            (x: 0, y: 0),
            (x: max(width / 2, 0), y: max(height / 2, 0)),
            (x: max(width - 1, 0), y: max(height - 1, 0)),
            (x: max(width / 3, 0), y: max(height / 3, 0)),
            (x: max((width * 2) / 3, 0), y: max((height * 2) / 3, 0))
        ]

        let pixels = samplePoints.map { point -> String in
            let offset = point.y * bytesPerRow + point.x * 4
            let b = data[offset]
            let g = data[offset + 1]
            let r = data[offset + 2]
            let a = data[offset + 3]
            return "(\(point.x),\(point.y))=\(r),\(g),\(b),\(a)"
        }.joined(separator: " | ")

        debugLog("\(label) sample pixels [\(pixels)]")
    }

    func captureCurrentDisplay() throws -> CapturedScreen {
        let hasPermission = permissionController.hasAccess
        debugLog("captureCurrentDisplay start; preflight=\(hasPermission)")
        logVisibleWindowDiagnostics()

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

        guard let selection = selectedScreenForCapture(),
              let compositeImage = captureScreenImageWithScreencapture(screen: selection.screen, displayIndex: selection.displayIndex) else {
            log("all capture backends returned nil")
            return nil
        }
        guard let displayID = selection.screen.displayID else { return nil }

        let frame = selection.screen.frame
        let scaleX = CGFloat(compositeImage.width) / frame.width
        let scaleY = CGFloat(compositeImage.height) / frame.height
        return CapturedScreen(
            displayID: displayID,
            frame: frame,
            image: compositeImage,
            scaleX: scaleX,
            scaleY: scaleY
        )
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
        logImageDiagnostics(image, label: "ScreenCaptureKit rect backend")
        saveDebugImage(image, named: "rect-backend")
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
        logImageDiagnostics(image, label: "ScreenCaptureKit display-filter backend")
        saveDebugImage(image, named: "display-filter-backend")
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

    private func captureScreenImageWithScreencapture(screen: NSScreen, displayIndex: Int) -> CGImage? {
        debugLog("fallback screencapture backend start displayIndex=\(displayIndex) frame=\(NSStringFromRect(screen.frame))")
        let fileManager = FileManager.default
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            log("fallback screencapture backend: no caches directory")
            return nil
        }

        let captureDirectory = cachesDirectory
            .appendingPathComponent(cacheContainerName, isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)

        do {
            try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        } catch {
            log("Failed to create capture cache directory: \(error.localizedDescription)")
            return nil
        }

        let captureURL = captureDirectory
            .appendingPathComponent("scrshot_capture_\(UUID().uuidString)")
            .appendingPathExtension("png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let errorPipe = Pipe()

        process.arguments = [
            "-x",
            "-o",
            "-t", "png",
            "-D", "\(displayIndex)",
            captureURL.path
        ]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log("screencapture launch failed: \(error.localizedDescription)")
            return nil
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !errorData.isEmpty, let errorOutput = String(data: errorData, encoding: .utf8) {
            log("screencapture stderr: \(errorOutput)")
        }

        guard process.terminationStatus == 0 else {
            log("screencapture failed with status \(process.terminationStatus)")
            return nil
        }

        guard waitForCaptureFile(at: captureURL, fileManager: fileManager),
              let imageData = try? Data(contentsOf: captureURL),
              !imageData.isEmpty,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            log("screencapture did not produce a readable PNG at \(captureURL.path)")
            return nil
        }

        lastCaptureURL = captureURL
        debugLog("scrshot raw capture saved at: \(captureURL.path) image=\(image.width)x\(image.height)")
        logImageDiagnostics(image, label: "screencapture fallback backend")
        return image
    }

    private func waitForCaptureFile(at url: URL, fileManager: FileManager) -> Bool {
        for _ in 0..<20 {
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? NSNumber,
               fileSize.intValue > 0 {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
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
