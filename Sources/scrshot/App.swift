import SwiftUI
import AppKit
import AVFoundation
import Security

struct DevelopmentEnvironmentDiagnostics {
    let bundlePath: String
    let bundleIdentifier: String
    let teamIdentifier: String

    var isRunningFromDerivedData: Bool {
        bundlePath.contains("/DerivedData/")
    }

    var isAdHocSigned: Bool {
        teamIdentifier == "nil" || teamIdentifier == "not set"
    }

    var likelyCausesTCCPermissionMismatch: Bool {
        isRunningFromDerivedData || isAdHocSigned
    }

    var summary: String {
        "bundlePath=\(bundlePath) bundleIdentifier=\(bundleIdentifier) teamIdentifier=\(teamIdentifier) runningFromDerivedData=\(isRunningFromDerivedData) adHocSigned=\(isAdHocSigned)"
    }
}

struct AppInstanceCoordinator {
    struct RunningApp: Equatable {
        let processIdentifier: pid_t
    }

    let bundleIdentifier: String?
    let currentProcessIdentifier: pid_t
    let runningApplicationsProvider: (String) -> [RunningApp]

    init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        runningApplicationsProvider: @escaping (String) -> [RunningApp] = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .map { RunningApp(processIdentifier: $0.processIdentifier) }
        }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.currentProcessIdentifier = currentProcessIdentifier
        self.runningApplicationsProvider = runningApplicationsProvider
    }

    func existingInstanceProcessIdentifier() -> pid_t? {
        guard let bundleIdentifier else { return nil }
        return runningApplicationsProvider(bundleIdentifier)
            .map(\.processIdentifier)
            .first(where: { $0 != currentProcessIdentifier })
    }
}

struct PermissionPreflightPolicy {
    static let skipEnvironmentKey = "SCRSHOT_SKIP_PERMISSION_PREFLIGHT"

    let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    var shouldRunOnLaunch: Bool {
        if environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        if let value = environment[Self.skipEnvironmentKey]?.lowercased(),
           ["1", "true", "yes"].contains(value) {
            return false
        }
        return true
    }
}

struct PermissionStatusSnapshot {
    let screenCaptureGranted: Bool
    let microphoneStatus: AVAuthorizationStatus

    static func current(
        screenCapturePermissionController: ScreenCapturePermissionController = .shared,
        microphonePermissionController: MicrophonePermissionController = .shared
    ) -> PermissionStatusSnapshot {
        PermissionStatusSnapshot(
            screenCaptureGranted: screenCapturePermissionController.hasAccess,
            microphoneStatus: microphonePermissionController.authorizationStatus
        )
    }

    var screenCaptureSummary: String {
        screenCaptureGranted ? "Allowed" : "Not Allowed"
    }

    var microphoneSummary: String {
        switch microphoneStatus {
        case .authorized:
            return "Allowed"
        case .notDetermined:
            return "Not Requested"
        case .denied, .restricted:
            return "Not Allowed"
        @unknown default:
            return "Unknown"
        }
    }
}

struct DevelopmentAppRelaunchCoordinator {
    static let relaunchedEnvironmentKey = "SCRSHOT_DEV_RELAUNCHED"

    let environment: [String: String]
    let fileManager: FileManager
    let appLauncher: (URL, [String: String]) throws -> Void

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        appLauncher: @escaping (URL, [String: String]) throws -> Void = DevelopmentAppRelaunchCoordinator.defaultAppLauncher
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.appLauncher = appLauncher
    }

    func shouldRelaunch(diagnostics: DevelopmentEnvironmentDiagnostics) -> Bool {
        guard diagnostics.likelyCausesTCCPermissionMismatch else { return false }
        guard environment["XCTestConfigurationFilePath"] == nil else { return false }
        guard environment[Self.relaunchedEnvironmentKey] != "1" else { return false }
        return true
    }

    func relaunchFromStableDevAppIfNeeded(bundle: Bundle) throws -> Bool {
        let diagnostics = try currentDiagnostics(for: bundle)
        guard shouldRelaunch(diagnostics: diagnostics) else { return false }

        let sourceAppURL = URL(fileURLWithPath: bundle.bundlePath, isDirectory: true)
        let stableAppURL = stableDevAppURL()
        try installStableDevApp(from: sourceAppURL, to: stableAppURL)
        try launchStableDevApp(at: stableAppURL)
        return true
    }

    private func currentDiagnostics(for bundle: Bundle) throws -> DevelopmentEnvironmentDiagnostics {
        let bundlePath = bundle.bundlePath
        let bundleIdentifier = bundle.bundleIdentifier ?? "nil"
        let teamIdentifier = try signingTeamIdentifier(for: bundlePath) ?? "nil"
        return DevelopmentEnvironmentDiagnostics(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier
        )
    }

    private func stableDevAppURL() -> URL {
        let homeDirectory = environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.homeDirectoryForCurrentUser
        let applicationsDirectory = homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        return applicationsDirectory.appendingPathComponent("scrshot-dev.app", isDirectory: true)
    }

    private func installStableDevApp(from sourceAppURL: URL, to stableAppURL: URL) throws {
        try fileManager.createDirectory(at: stableAppURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: stableAppURL.path) {
            try fileManager.removeItem(at: stableAppURL)
        }
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: [sourceAppURL.path, stableAppURL.path]
        )
        try signStableDevApp(at: stableAppURL)
    }

    private func signStableDevApp(at appURL: URL) throws {
        let signingIdentity = try appleDevelopmentSigningIdentity() ?? "-"
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--force", "--deep", "--sign", signingIdentity, "--timestamp=none", appURL.path]
        )
    }

    private func launchStableDevApp(at appURL: URL) throws {
        var relaunchedEnvironment = environment
        relaunchedEnvironment[Self.relaunchedEnvironmentKey] = "1"
        try appLauncher(appURL, relaunchedEnvironment)
    }

    func executableURL(forAppAt appURL: URL) throws -> URL {
        guard let bundle = Bundle(url: appURL),
              let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String,
              !executableName.isEmpty else {
            throw NSError(
                domain: "DevelopmentAppRelaunchCoordinator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing CFBundleExecutable in \(appURL.path)"]
            )
        }

        return appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)
    }

    private func appleDevelopmentSigningIdentity() throws -> String? {
        let output = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-identity", "-v", "-p", "codesigning"],
            captureOutput: true
        )
        return output?
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let range = line.range(of: "\"Apple Development:") else { return nil }
                return String(line[range.lowerBound...].dropFirst().dropLast())
            }
            .first
    }

    private static func defaultAppLauncher(appURL: URL, environment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = launchArguments(forAppAt: appURL, environment: environment)
        try process.run()
    }

    static func launchArguments(forAppAt appURL: URL, environment: [String: String]) -> [String] {
        var arguments = ["-na", appURL.path]
        if let relaunchedFlag = environment[Self.relaunchedEnvironmentKey] {
            arguments.append(contentsOf: ["--env", "\(Self.relaunchedEnvironmentKey)=\(relaunchedFlag)"])
        }
        return arguments
    }

    private func signingTeamIdentifier(for bundlePath: String) throws -> String? {
        let url = URL(fileURLWithPath: bundlePath) as CFURL
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
        guard infoStatus == errSecSuccess,
              let signingInformation = signingInformation as? [String: Any] else {
            return nil
        }

        return signingInformation[kSecCodeInfoTeamIdentifier as String] as? String
    }

    @discardableResult
    private func runProcess(
        executableURL: URL,
        arguments: [String],
        captureOutput: Bool = false
    ) throws -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        if captureOutput {
            process.standardOutput = outputPipe
        }
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "DevelopmentAppRelaunchCoordinator",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }

        guard captureOutput else { return nil }
        return String(data: outputData, encoding: .utf8)
    }
}

@MainActor
final class AppPermissionCoordinator {
    private let screenCapturePermissionController: ScreenCapturePermissionController
    private let microphonePermissionController: MicrophonePermissionController
    private let openPrivacyPane: (String) -> Void

    init(
        screenCapturePermissionController: ScreenCapturePermissionController = .shared,
        microphonePermissionController: MicrophonePermissionController = .shared,
        openPrivacyPane: @escaping (String) -> Void = { anchor in
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    ) {
        self.screenCapturePermissionController = screenCapturePermissionController
        self.microphonePermissionController = microphonePermissionController
        self.openPrivacyPane = openPrivacyPane
    }

    func preflightOnLaunch(recordingAudioSource: AppPreferences.RecordingAudioSource) {
        let screenCaptureGranted = screenCapturePermissionController.hasAccess
        AppLogger.shared.info(
            .appDiagnostics,
            "permission preflight screenCapture granted=\(screenCaptureGranted) prompted=\(screenCapturePermissionController.hasRequestedSystemPrompt)"
        )
        if !screenCaptureGranted {
            let requestResult = screenCapturePermissionController.requestAccessIfNeeded()
            AppLogger.shared.info(
                .appDiagnostics,
                "permission preflight screenCapture requestResult=\(requestResult) prompted=\(screenCapturePermissionController.hasRequestedSystemPrompt)"
            )
        }

        guard recordingAudioSource.capturesMicrophone else {
            AppLogger.shared.info(.appDiagnostics, "permission preflight microphone skipped for audioSource=\(recordingAudioSource.rawValue)")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let microphoneGranted = self.microphonePermissionController.hasAccess
            AppLogger.shared.info(
                .appDiagnostics,
                "permission preflight microphone granted=\(microphoneGranted) status=\(self.microphonePermissionController.authorizationStatus.rawValue) prompted=\(self.microphonePermissionController.hasRequestedSystemPrompt)"
            )
            if !microphoneGranted {
                let requestResult = await self.microphonePermissionController.requestAccessIfNeeded()
                AppLogger.shared.info(
                    .appDiagnostics,
                    "permission preflight microphone requestResult=\(requestResult) status=\(self.microphonePermissionController.authorizationStatus.rawValue)"
                )
            }
        }
    }

    func ensurePermissionsForCapture() -> Bool {
        if screenCapturePermissionController.hasAccess {
            return true
        }
        if !screenCapturePermissionController.requestAccessIfNeeded() {
            openPrivacyPane("Privacy_ScreenCapture")
            return false
        }
        return screenCapturePermissionController.hasAccess
    }

    func ensurePermissionsForRecording(audioSource: AppPreferences.RecordingAudioSource) async -> Bool {
        if !screenCapturePermissionController.hasAccess {
            if !screenCapturePermissionController.requestAccessIfNeeded() {
                openPrivacyPane("Privacy_ScreenCapture")
                return false
            }
            guard screenCapturePermissionController.hasAccess else {
                return false
            }
        }

        guard audioSource.capturesMicrophone else { return true }
        if microphonePermissionController.hasAccess {
            return true
        }
        let didPrompt = await microphonePermissionController.requestAccessIfNeeded()
        if !didPrompt && !microphonePermissionController.hasAccess {
            openPrivacyPane("Privacy_Microphone")
            return false
        }
        return microphonePermissionController.hasAccess
    }
}

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
    private let appInstanceCoordinator = AppInstanceCoordinator()
    private let developmentAppRelaunchCoordinator = DevelopmentAppRelaunchCoordinator()
    private let permissionPreflightPolicy = PermissionPreflightPolicy()
    private let terminationStateTracker = AppTerminationStateTracker()
    private lazy var coordinator = AppCoordinator(preferences: preferences)
    private lazy var preferencesWindowController = PreferencesWindowController(preferences: preferences)
    private var statusItemController: StatusItemController?
    private var preferencesObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCrashMonitor.installUncaughtExceptionLogger()
        if activateExistingInstanceIfNeeded() {
            return
        }
        if relaunchFromStableDevAppIfNeeded() {
            return
        }
        let didPreviousRunCrash = terminationStateTracker.markLaunchStarted()
        logRuntimeDiagnostics()
        AppLogger.shared.info(.appLifecycle, "applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        applyTheme()
        launchAtLoginController.apply(isEnabled: preferences.launchAtLogin)
        coordinator.start()
        if permissionPreflightPolicy.shouldRunOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.coordinator.preflightPermissionsOnLaunch()
            }
        } else {
            AppLogger.shared.info(.appDiagnostics, "permission preflight skipped on launch")
        }
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
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        DispatchQueue.main.async {
            CrashAlertPresenter.presentIfNeeded(
                didPreviousRunCrash: didPreviousRunCrash,
                logFilePath: AppLogger.shared.currentLogFilePath
            )
        }
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        guard let existingPID = appInstanceCoordinator.existingInstanceProcessIdentifier(),
              let runningApp = NSRunningApplication(processIdentifier: existingPID) else {
            return false
        }

        AppLogger.shared.info(.appLifecycle, "existing instance detected pid=\(existingPID); activating it and terminating current launch")
        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.terminate(nil)
        return true
    }

    private func relaunchFromStableDevAppIfNeeded() -> Bool {
        do {
            let didRelaunch = try developmentAppRelaunchCoordinator.relaunchFromStableDevAppIfNeeded(bundle: .main)
            if didRelaunch {
                AppLogger.shared.info(.appDiagnostics, "relaunching from stable dev app to preserve macOS permissions")
                NSApp.terminate(nil)
            }
            return didRelaunch
        } catch {
            AppLogger.shared.error(.appDiagnostics, "failed to relaunch stable dev app: \(error.localizedDescription)")
            return false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
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
            let diagnostics = DevelopmentEnvironmentDiagnostics(
                bundlePath: bundlePath,
                bundleIdentifier: bundleIdentifier,
                teamIdentifier: signingInfo.teamIdentifier
            )
            AppLogger.shared.debug(.appDiagnostics, "developmentEnvironment \(diagnostics.summary)")
            if diagnostics.likelyCausesTCCPermissionMismatch {
                AppLogger.shared.error(
                    .appDiagnostics,
                    "unstable development app identity may break macOS permissions; \(diagnostics.summary)"
                )
            }
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
    private let permissionCoordinator = AppPermissionCoordinator()
    private let captureSoundPlayer = CaptureSoundPlayer()
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

    func preflightPermissionsOnLaunch() {
        permissionCoordinator.preflightOnLaunch(recordingAudioSource: preferences.recordingAudioSource)
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
            if let captureURL = screenCaptureService.lastCaptureURL {
                AppLogger.shared.debug(.appCoordinator, "using raw capture file: \(captureURL.path)")
            }
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
            let shouldCopy = preferences.exportBehavior != .saveOnly
            let shouldSave = preferences.exportBehavior != .copyOnly

            if shouldCopy {
                try clipboardManager.copy(image: image)
            }

            var savedFileURL: URL?
            if shouldSave {
                savedFileURL = try imageSaver.save(
                    image: image,
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
}
