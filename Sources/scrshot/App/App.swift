import SwiftUI
import AppKit

@main
struct ScrshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var statusItemController = StatusItemController.shared

    var body: some Scene {
        MenuBarExtra {
            StatusItemMenuBarContent(controller: statusItemController)
        } label: {
            Image(systemName: statusItemController.menuBarSymbolName)
        }

        Settings {
            PreferencesSceneView(preferences: AppPreferences.shared)
        }
        .commands {
            EditorCommandMenu()
        }

        Window("About scrshot", id: AppSceneID.about) {
            AboutSceneView(versionTitle: statusItemController.versionMenuTitle)
        }
        .defaultSize(width: 300, height: 260)
        .windowResizability(.contentSize)
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
    private static let openPreferencesOnLaunchEnvironmentKey = "SCRSHOT_OPEN_PREFERENCES_ON_LAUNCH"

    private let preferences = AppPreferences.shared
    private let launchAtLoginController = LaunchAtLoginController()
    private let appInstanceCoordinator = AppInstanceCoordinator()
    private let terminationStateTracker = AppTerminationStateTracker()
    private lazy var coordinator = AppCoordinator(preferences: preferences)
    private lazy var preferencesWindowController = PreferencesWindowController(preferences: preferences)
    private let statusItemController = StatusItemController.shared
    private var preferencesObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !XcodePreviewSupport.isRunning else { return }
        AppCrashMonitor.installUncaughtExceptionLogger()
        if terminateExistingInstancesIfNeeded() {
            return
        }
        let didPreviousRunCrash = terminationStateTracker.markLaunchStarted()
        logRuntimeDiagnostics()
        AppLogger.shared.info(.appLifecycle, "applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        applyTheme()
        launchAtLoginController.apply(isEnabled: preferences.launchAtLogin)
        coordinator.start()
        coordinator.logPermissionStatusOnLaunch()
        statusItemController.configure(
            onToggleRecording: { [weak self] in
                self?.coordinator.toggleRecording()
            },
            isRecordingProvider: { [weak self] in
                self?.coordinator.isRecording ?? false
            },
            recordingAudioSourceProvider: { [weak self] in
                self?.preferences.recordingAudioSource ?? .noAudio
            },
            onSelectRecordingAudioSource: { [weak self] source in
                self?.preferences.recordingAudioSource = source
            }
        )
        SettingsWindowPresenter.showHandler = { [weak self] in
            self?.preferencesWindowController.show()
        }
        coordinator.onRecordingStateChange = { [weak self] isRecording in
            self?.statusItemController.setRecordingState(isRecording)
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
                self.statusItemController.refreshRecordingAudioSource(self.preferences.recordingAudioSource)
            }
        }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        if shouldOpenPreferencesOnLaunch {
            DispatchQueue.main.async {
                SettingsWindowPresenter.show()
            }
        }
        DispatchQueue.main.async {
            CrashAlertPresenter.presentIfNeeded(
                didPreviousRunCrash: didPreviousRunCrash,
                logFilePath: AppLogger.shared.currentLogFilePath
            )
        }
    }

    private func terminateExistingInstancesIfNeeded() -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        let existingPIDs = appInstanceCoordinator.existingInstanceProcessIdentifiers()
        guard !existingPIDs.isEmpty else {
            return false
        }

        AppLogger.shared.info(.appLifecycle, "another instance is already running")
        let runningApps = existingPIDs.compactMap(NSRunningApplication.init(processIdentifier:))
        runningApps.forEach { $0.terminate() }

        let remainingApps = waitForRunningApplicationsToTerminate(runningApps)
        guard !remainingApps.isEmpty else {
            return false
        }

        presentRunningInstanceAlert()
        NSApp.terminate(nil)
        return true
    }

    private func waitForRunningApplicationsToTerminate(_ applications: [NSRunningApplication]) -> [NSRunningApplication] {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            let remainingApplications = applications.filter { !$0.isTerminated }
            if remainingApplications.isEmpty {
                return []
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return applications.filter { !$0.isTerminated }
    }

    private func presentRunningInstanceAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Another copy of scrshot is already running."
        alert.informativeText = "scrshot tried to close the existing copy, but it did not quit. Quit the existing copy manually, then start scrshot again."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }

    private var shouldOpenPreferencesOnLaunch: Bool {
        if let value = ProcessInfo.processInfo.environment[Self.openPreferencesOnLaunchEnvironmentKey]?.lowercased() {
            return ["1", "true", "yes"].contains(value)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        SettingsWindowPresenter.showHandler = nil
        terminationStateTracker.markTerminatedCleanly()
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

private struct AboutSceneView: View {
    let versionTitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIconImage)
                .resizable()
                .frame(width: 56, height: 56)

            VStack(spacing: 6) {
                Text("scrshot")
                    .font(.title2.weight(.semibold))
                Text(versionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Fast screenshot capture and annotation for macOS.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Link("Privacy Policy", destination: URL(string: "https://github.com/Warrfie/scrshot/blob/main/docs/PRIVACY.md")!)
                Link("GitHub", destination: URL(string: "https://github.com/Warrfie/scrshot")!)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(AboutWindowConfigurator())
    }

    private var appIconImage: NSImage {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            return iconImage
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

private struct AboutWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if DEBUG
struct AboutSceneView_Previews: PreviewProvider {
    static var previews: some View {
        AboutSceneView(versionTitle: "Version 1.2 (1)")
    }
}
#endif
@MainActor
final class AppCoordinator {
    private let hotkeyManager = HotkeyManager()
    private let screenCaptureService = ScreenCaptureService()
    private let screenRecordingService = ScreenRecordingService()
    private let clipboardManager = ClipboardManager()
    private let imageSaver = ImageSaver()
    private let permissionCoordinator = AppPermissionCoordinator()
    private let captureSoundPlayer = CaptureSoundPlayer()
    private let preferences: AppPreferences
    private var editorController: ScreenshotEditorWindowController?
    private var isOpeningEditor = false
    private var lastCaptureRequestDate: Date?
    private var recordingDirectoryAccess: SecurityScopedDirectoryAccess?
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

    func logPermissionStatusOnLaunch() {
        permissionCoordinator.logStatusOnLaunch(recordingAudioSource: preferences.recordingAudioSource)
    }

    func applyPreferences() {
        hotkeyManager.setCaptureHotkey(preferences.captureHotkey)
        AppLogger.shared.info(
            .appCoordinator,
            "applied preferences hotkey=\(preferences.captureHotkey.keyCode):\(preferences.captureHotkey.modifiers) theme=\(preferences.theme.rawValue)"
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
        AppLogger.shared.info(.appCoordinator, "capture requested")
        guard permissionCoordinator.ensurePermissionsForCapture() else {
            AppLogger.shared.debug(.appCoordinator, "capture aborted because screen recording permission is unavailable")
            return
        }
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
            _ = captureSoundPlayer.playCaptureSoundIfEnabled(preferences: preferences)
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
        guard await permissionCoordinator.ensurePermissionsForRecording(audioSource: preferences.recordingAudioSource) else {
            AppLogger.shared.debug(.appCoordinator, "recording start aborted because required permissions are unavailable")
            return
        }
        do {
            try ensureSaveDirectoryAccess()
            let directoryAccess = try preferences.makeSaveDirectoryAccess()
            _ = try await screenRecordingService.startRecording(
                options: .init(
                    directory: directoryAccess.url,
                    fileNamePrefix: preferences.fileNamePrefix,
                    timestampTemplate: preferences.timestampTemplate,
                    audioSource: preferences.recordingAudioSource,
                    fileFormat: preferences.recordingFileFormat
                )
            )
            recordingDirectoryAccess = directoryAccess
        } catch {
            recordingDirectoryAccess = nil
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
            recordingDirectoryAccess = nil
            onRecordingStateChange?(false)
        } catch {
            recordingDirectoryAccess = nil
            onRecordingStateChange?(false)
            AppLogger.shared.error(.appCoordinator, "failed to stop recording: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func finalize(_ image: CGImage) {
        do {
            let shouldCopy = preferences.exportBehavior != .saveOnly
            let shouldSave = preferences.exportBehavior != .copyOnly

            if shouldCopy {
                try clipboardManager.copy(image: image)
            }

            var savedFileURL: URL?
            if shouldSave {
                try ensureSaveDirectoryAccess()
                savedFileURL = try preferences.withSaveDirectoryAccess { directory in
                    try imageSaver.save(
                        image: image,
                        options: ImageSaver.Options(
                            directory: directory,
                            fileNamePrefix: preferences.fileNamePrefix,
                            timestampTemplate: preferences.timestampTemplate
                        )
                    )
                }
            }

            if preferences.revealSavedFile, let savedFileURL {
                NSWorkspace.shared.activateFileViewerSelecting([savedFileURL])
            }
        } catch {
            AppLogger.shared.error(.appCoordinator, "failed to finalize screenshot: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func ensureSaveDirectoryAccess() throws {
        guard !preferences.hasSaveDirectoryBookmark else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Save Folder"
        panel.message = "scrshot needs permission to save screenshots. Choose a folder in Documents or any other folder you want to use."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        let preferredDirectory = preferences.saveDirectoryURL
        if FileManager.default.fileExists(atPath: preferredDirectory.path) {
            panel.directoryURL = preferredDirectory
        } else {
            panel.directoryURL = preferredDirectory.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            throw AppPreferences.SaveDirectoryError.failedToResolveBookmark(
                NSError(
                    domain: "scrshot.saveDirectory",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Save folder permission was not granted."]
                )
            )
        }

        try preferences.updateSaveDirectory(url)
    }
}
