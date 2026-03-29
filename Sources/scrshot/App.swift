import SwiftUI
import AppKit
import Security

@main
struct ScrshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            EditorCommandMenu()
        }
    }
}

struct EditorCommandMenu: Commands {
    var body: some Commands {
        CommandMenu("Editor") {
            Button("Fit to Window") {
                NSApp.sendAction(#selector(ScreenshotEditorViewController.fitToWindowAction(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("0", modifiers: [.command])

            Button("Zoom In") {
                NSApp.sendAction(#selector(ScreenshotEditorViewController.zoomInAction(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("=", modifiers: [.command])

            Button("Zoom Out") {
                NSApp.sendAction(#selector(ScreenshotEditorViewController.zoomOutAction(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button("Delete Selection") {
                NSApp.sendAction(#selector(ScreenshotEditorCanvasView.deleteSelectionAction(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences.shared
    private let launchAtLoginController = LaunchAtLoginController()
    private lazy var coordinator = AppCoordinator(preferences: preferences)
    private lazy var preferencesWindowController = PreferencesWindowController(preferences: preferences)
    private var statusItemController: StatusItemController?
    private var preferencesObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logRuntimeDiagnostics()
        AppLogger.shared.info(.appLifecycle, "applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        applyTheme()
        launchAtLoginController.apply(isEnabled: preferences.launchAtLogin)
        coordinator.start()
        statusItemController = StatusItemController(
            preferencesWindowController: preferencesWindowController,
            onToggleRecording: { [weak self] in
                self?.coordinator.toggleRecording()
            },
            isRecordingProvider: { [weak self] in
                self?.coordinator.isRecording ?? false
            },
            recordingAudioSourceProvider: { [weak self] in
                self?.preferences.recordingAudioSource ?? .systemAudio
            },
            onSelectRecordingAudioSource: { [weak self] source in
                self?.preferences.recordingAudioSource = source
            }
        )
        coordinator.onRecordingStateChange = { [weak self] isRecording in
            self?.statusItemController?.setRecordingState(isRecording)
        }
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .appPreferencesDidChange,
            object: preferences,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyTheme()
                self.launchAtLoginController.apply(isEnabled: self.preferences.launchAtLogin)
                self.coordinator.applyPreferences()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        AppLogger.shared.info(.appLifecycle, "applicationWillTerminate")
    }

    private func applyTheme() {
        NSApp.appearance = preferences.theme.appearance
        AppLogger.shared.info(.appLifecycle, "applied theme \(preferences.theme.rawValue)")
    }

    private func logRuntimeDiagnostics() {
        let bundle = Bundle.main
        let bundlePath = bundle.bundlePath
        let executablePath = bundle.executableURL?.path ?? "nil"
        let bundleIdentifier = bundle.bundleIdentifier ?? "nil"
        let receiptPath = bundle.appStoreReceiptURL?.path ?? "nil"
        let hasEmbeddedReceipt = FileManager.default.fileExists(atPath: receiptPath)
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

        AppLogger.shared.debug(.appDiagnostics, "logFilePath=\(AppLogger.shared.currentLogFilePath)")
        AppLogger.shared.debug(.appDiagnostics, "bundlePath=\(bundlePath)")
        AppLogger.shared.debug(.appDiagnostics, "executablePath=\(executablePath)")
        AppLogger.shared.debug(.appDiagnostics, "bundleIdentifier=\(bundleIdentifier)")
        AppLogger.shared.debug(.appDiagnostics, "receiptPath=\(receiptPath) exists=\(hasEmbeddedReceipt)")
        AppLogger.shared.debug(.appDiagnostics, "isSandboxed=\(isSandboxed)")
        AppLogger.shared.debug(.appDiagnostics, "screenCapturePreflight=\(CGPreflightScreenCaptureAccess())")

        if let signingInfo = signingDiagnostics(for: bundlePath) {
            AppLogger.shared.debug(.appDiagnostics, "signing subject=\(signingInfo.subject)")
            AppLogger.shared.debug(.appDiagnostics, "signing teamIdentifier=\(signingInfo.teamIdentifier)")
            AppLogger.shared.debug(.appDiagnostics, "signing identifier=\(signingInfo.identifier)")
        } else {
            AppLogger.shared.debug(.appDiagnostics, "signing diagnostics unavailable")
        }
    }

    private func signingDiagnostics(for bundlePath: String) -> (subject: String, teamIdentifier: String, identifier: String)? {
        let url = URL(fileURLWithPath: bundlePath) as CFURL
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            AppLogger.shared.debug(.appDiagnostics, "SecStaticCodeCreateWithPath failed status=\(createStatus)")
            return nil
        }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
        guard infoStatus == errSecSuccess,
              let signingInformation = signingInformation as? [String: Any] else {
            AppLogger.shared.debug(.appDiagnostics, "SecCodeCopySigningInformation failed status=\(infoStatus)")
            return nil
        }

        let identifier = signingInformation[kSecCodeInfoIdentifier as String] as? String ?? "nil"
        let teamIdentifier = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String ?? "nil"

        let subject: String
        if let certificates = signingInformation[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let firstCertificate = certificates.first,
           let summary = SecCertificateCopySubjectSummary(firstCertificate) as String? {
            subject = summary
        } else {
            subject = "nil"
        }

        return (subject: subject, teamIdentifier: teamIdentifier, identifier: identifier)
    }
}
@MainActor
final class AppCoordinator {
    private let hotkeyManager = HotkeyManager()
    private let screenCaptureService = ScreenCaptureService()
    private let screenRecordingService = ScreenRecordingService()
    private let clipboardManager = ClipboardManager()
    private let imageSaver = ImageSaver()
    private let preferences: AppPreferences
    private var editorController: ScreenshotEditorWindowController?
    private var isOpeningEditor = false
    private var lastCaptureRequestDate: Date?
    var onRecordingStateChange: ((Bool) -> Void)?

    var isRecording: Bool {
        screenRecordingService.isRecording
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        screenRecordingService.onRecordingStateChanged = { [weak self] isRecording in
            self?.onRecordingStateChange?(isRecording)
        }
    }

    func start() {
        hotkeyManager.onCapture = { [weak self] in
            self?.captureFullscreen()
        }
        hotkeyManager.start()
        applyPreferences()
    }

    func applyPreferences() {
        hotkeyManager.setCaptureHotkey(preferences.captureHotkey)
        AppLogger.shared.info(
            .appCoordinator,
            "applied preferences hotkey=\(preferences.captureHotkey.keyCode):\(preferences.captureHotkey.modifiers) theme=\(preferences.theme.rawValue) saveDirectory=\(preferences.saveDirectoryURL.path)"
        )
    }

    func toggleRecording() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.screenRecordingService.isRecording {
                await self.stopRecording()
            } else {
                await self.startRecording()
            }
        }
    }

    private func captureFullscreen() {
        let now = Date()
        if let lastCaptureRequestDate, now.timeIntervalSince(lastCaptureRequestDate) < 0.35 {
            AppLogger.shared.debug(.appCoordinator, "ignored duplicate capture request within debounce window")
            return
        }
        lastCaptureRequestDate = now

        guard editorController == nil, !isOpeningEditor else {
            AppLogger.shared.debug(.appCoordinator, "ignored capture because editor is already open or opening")
            NSSound.beep()
            return
        }
        isOpeningEditor = true

        do {
            let capturedDisplay = try screenCaptureService.captureCurrentDisplay()
            if let captureURL = screenCaptureService.lastCaptureURL {
                AppLogger.shared.debug(.appCoordinator, "using raw capture file: \(captureURL.path)")
            }
            openEditor(with: capturedDisplay.image, preferredDisplayID: capturedDisplay.displayID)
        } catch {
            isOpeningEditor = false
            AppLogger.shared.error(.appCoordinator, "full-screen capture failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func openEditor(with image: CGImage, preferredDisplayID: CGDirectDisplayID?) {
        let controller = ScreenshotEditorWindowController(image: image, preferredDisplayID: preferredDisplayID)
        controller.onComplete = { [weak self] editedImage in
            guard let self else { return }
            self.isOpeningEditor = false
            self.editorController = nil
            guard let editedImage else { return }
            self.finalize(editedImage)
        }
        editorController = controller
        let preferredDisplayDescription = preferredDisplayID.map(String.init) ?? "nil"
        AppLogger.shared.debug(.appCoordinator, "openEditor preferredDisplayID=\(preferredDisplayDescription) image=\(image.width)x\(image.height)")
        controller.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak controller] in
            guard let self, let controller, self.editorController === controller else { return }
            guard let window = controller.window, window.isVisible else {
                AppLogger.shared.debug(.appCoordinator, "editor window not visible after delay; retrying show")
                controller.presentVisibilityAlert()
                controller.show()
                return
            }
            AppLogger.shared.debug(.appCoordinator, "editor window visible frame=\(NSStringFromRect(window.frame))")
        }
    }

    private func startRecording() async {
        do {
            _ = try await screenRecordingService.startRecording(
                options: .init(
                    directory: preferences.saveDirectoryURL,
                    fileNamePrefix: preferences.fileNamePrefix,
                    timestampTemplate: preferences.timestampTemplate,
                    audioSource: preferences.recordingAudioSource,
                    fileFormat: preferences.recordingFileFormat
                )
            )
        } catch {
            onRecordingStateChange?(false)
            AppLogger.shared.error(.appCoordinator, "failed to start recording: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func stopRecording() async {
        do {
            let outputURL = try await screenRecordingService.stopRecording()
            if preferences.revealSavedFile {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
        } catch {
            onRecordingStateChange?(false)
            AppLogger.shared.error(.appCoordinator, "failed to stop recording: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func finalize(_ image: CGImage) {
        do {
            let outputImage = verticallyFlippedImage(from: image) ?? image
            let shouldCopy = preferences.exportBehavior != .saveOnly
            let shouldSave = preferences.exportBehavior != .copyOnly

            if shouldCopy {
                try clipboardManager.copy(image: outputImage)
            }

            var savedFileURL: URL?
            if shouldSave {
                savedFileURL = try imageSaver.save(
                    image: outputImage,
                    options: ImageSaver.Options(
                        directory: preferences.saveDirectoryURL,
                        fileNamePrefix: preferences.fileNamePrefix,
                        timestampTemplate: preferences.timestampTemplate
                    )
                )
            }

            if preferences.revealSavedFile, let savedFileURL {
                NSWorkspace.shared.activateFileViewerSelecting([savedFileURL])
            }
        } catch {
            AppLogger.shared.error(.appCoordinator, "failed to finalize screenshot: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func verticallyFlippedImage(from image: CGImage) -> CGImage? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
