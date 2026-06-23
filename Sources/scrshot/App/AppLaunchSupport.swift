import AppKit
import AVFoundation
import Security

enum AppSceneID {
    static let about = "about"
}

enum XcodePreviewSupport {
    static let isRunning = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

enum TestRuntimeSupport {
    static var isRunning: Bool {
        isRunning(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) || NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil
    }

    static func isRunning(environment: [String: String], arguments: [String]) -> Bool {
        if let value = environment["SCRSHOT_RUNNING_TESTS"]?.lowercased(),
           ["1", "true", "yes"].contains(value) {
            return true
        }
        let testEnvironmentKeys = [
            "XCTestConfigurationFilePath",
            "XCTestBundlePath",
            "XCTestSessionIdentifier",
        ]
        if testEnvironmentKeys.contains(where: { environment[$0] != nil }) {
            return true
        }
        return arguments.contains { argument in
            argument.contains(".xctest") || argument.hasPrefix("-XCTest")
        }
    }
}

struct AppInstanceCoordinator {
    static let disableSingleInstanceEnvironmentKey = "SCRSHOT_DISABLE_SINGLE_INSTANCE_ENFORCEMENT"
    static let knownBundleIdentifiers: Set<String> = [
        "io.github.Warrfie.scrshot",
        "com.warrfie.scrshot",
    ]

    struct RunningApp: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?

        init(
            processIdentifier: pid_t,
            bundleIdentifier: String? = nil
        ) {
            self.processIdentifier = processIdentifier
            self.bundleIdentifier = bundleIdentifier
        }
    }

    let bundleIdentifier: String?
    let currentProcessIdentifier: pid_t
    let environment: [String: String]
    let runningApplicationsProvider: (String?) -> [RunningApp]

    init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runningApplicationsProvider: @escaping (String?) -> [RunningApp] = { bundleIdentifier in
            let applications: [NSRunningApplication]
            if let bundleIdentifier {
                applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            } else {
                applications = NSWorkspace.shared.runningApplications
            }
            return applications.map {
                RunningApp(
                    processIdentifier: $0.processIdentifier,
                    bundleIdentifier: $0.bundleIdentifier
                )
            }
        }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.currentProcessIdentifier = currentProcessIdentifier
        self.environment = environment
        self.runningApplicationsProvider = runningApplicationsProvider
    }

    func existingInstanceProcessIdentifier() -> pid_t? {
        existingInstanceProcessIdentifiers().first
    }

    func existingInstanceProcessIdentifiers() -> [pid_t] {
        if let value = environment[Self.disableSingleInstanceEnvironmentKey]?.lowercased(),
           ["1", "true", "yes"].contains(value) {
            return []
        }
        let bundleIdentifiers = Self.knownBundleIdentifiers.union([bundleIdentifier].compactMap { $0 })
        let bundleMatches = bundleIdentifiers.flatMap { runningApplicationsProvider($0) }

        var seenProcessIdentifiers = Set<pid_t>()
        return bundleMatches
            .map(\.processIdentifier)
            .filter { $0 != currentProcessIdentifier }
            .filter { seenProcessIdentifiers.insert($0).inserted }
    }
}

struct PermissionStatusSnapshot {
    let screenCaptureGranted: Bool
    let microphoneStatus: AVAuthorizationStatus

    static func current(
        screenCapturePermissionController: ScreenCapturePermissionController = .shared,
        microphonePermissionController: MicrophonePermissionController = .shared
    ) -> PermissionStatusSnapshot {
        if XcodePreviewSupport.isRunning {
            return PermissionStatusSnapshot(
                screenCaptureGranted: true,
                microphoneStatus: .authorized
            )
        }
        return PermissionStatusSnapshot(
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

@MainActor
final class AppPermissionCoordinator {
    private let screenCapturePermissionController: ScreenCapturePermissionController
    private let microphonePermissionController: MicrophonePermissionController
    private let openPrivacyPane: (String) -> Void
    private let confirmOpenPrivacyPane: @MainActor (PermissionKind) -> Bool

    enum PermissionKind {
        case screenCapture
        case microphone

        var settingsAnchor: String {
            switch self {
            case .screenCapture:
                return "Privacy_ScreenCapture"
            case .microphone:
                return "Privacy_Microphone"
            }
        }

        var alertMessage: String {
            switch self {
            case .screenCapture:
                return "Screen Recording access is required."
            case .microphone:
                return "Microphone access is required."
            }
        }

        var alertDetails: String {
            switch self {
            case .screenCapture:
                return "scrshot needs Screen Recording access to capture screenshots and record your screen. Open System Settings and enable scrshot."
            case .microphone:
                return "scrshot needs Microphone access only when you choose a recording mode that captures microphone audio. Open System Settings and enable scrshot."
            }
        }
    }

    init(
        screenCapturePermissionController: ScreenCapturePermissionController = .shared,
        microphonePermissionController: MicrophonePermissionController = .shared,
        openPrivacyPane: @escaping (String) -> Void = { anchor in
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
                AppLogger.shared.error(.appDiagnostics, "failed to build privacy pane URL anchor=\(anchor)")
                return
            }
            AppLogger.shared.info(.appDiagnostics, "opening privacy pane anchor=\(anchor)")
            NSWorkspace.shared.open(url)
        },
        confirmOpenPrivacyPane: @escaping @MainActor (PermissionKind) -> Bool = { permissionKind in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = permissionKind.alertMessage
            alert.informativeText = permissionKind.alertDetails
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    ) {
        self.screenCapturePermissionController = screenCapturePermissionController
        self.microphonePermissionController = microphonePermissionController
        self.openPrivacyPane = openPrivacyPane
        self.confirmOpenPrivacyPane = confirmOpenPrivacyPane
    }

    func logStatusOnLaunch(recordingAudioSource: AppPreferences.RecordingAudioSource) {
        let screenCaptureGranted = screenCapturePermissionController.hasAccess
        AppLogger.shared.info(
            .appDiagnostics,
            "permission status screenCapture granted=\(screenCaptureGranted) prompted=\(screenCapturePermissionController.hasRequestedSystemPrompt)"
        )

        guard recordingAudioSource.capturesMicrophone else {
            AppLogger.shared.info(.appDiagnostics, "permission status microphone skipped for audioSource=\(recordingAudioSource.rawValue)")
            return
        }

        AppLogger.shared.info(
            .appDiagnostics,
            "permission status microphone granted=\(microphonePermissionController.hasAccess) status=\(microphonePermissionController.authorizationStatus.rawValue) prompted=\(microphonePermissionController.hasRequestedSystemPrompt)"
        )
    }

    func ensurePermissionsForCapture() -> Bool {
        if screenCapturePermissionController.hasAccess {
            return true
        }
        let hadRequestedScreenCapturePrompt = screenCapturePermissionController.hasRequestedSystemPrompt
        _ = screenCapturePermissionController.requestAccessIfNeeded()
        if screenCapturePermissionController.hasAccess {
            return true
        }
        if !hadRequestedScreenCapturePrompt && screenCapturePermissionController.hasRequestedSystemPrompt {
            return false
        }
        openPrivacyPaneIfConfirmed(.screenCapture)
        return false
    }

    func ensurePermissionsForRecording(audioSource: AppPreferences.RecordingAudioSource) async -> Bool {
        if !screenCapturePermissionController.hasAccess {
            let hadRequestedScreenCapturePrompt = screenCapturePermissionController.hasRequestedSystemPrompt
            _ = screenCapturePermissionController.requestAccessIfNeeded()
            if screenCapturePermissionController.hasAccess {
                return true
            }
            if !hadRequestedScreenCapturePrompt && screenCapturePermissionController.hasRequestedSystemPrompt {
                return false
            }
            openPrivacyPaneIfConfirmed(.screenCapture)
            return false
        }

        guard audioSource.capturesMicrophone else { return true }
        if microphonePermissionController.hasAccess {
            return true
        }
        let hadRequestedMicrophonePrompt = microphonePermissionController.hasRequestedSystemPrompt
        _ = await microphonePermissionController.requestAccessIfNeeded()
        if microphonePermissionController.hasAccess {
            return true
        }
        if !hadRequestedMicrophonePrompt && microphonePermissionController.hasRequestedSystemPrompt {
            return false
        }
        if !microphonePermissionController.hasAccess {
            openPrivacyPaneIfConfirmed(.microphone)
            return false
        }
        return true
    }

    private func openPrivacyPaneIfConfirmed(_ permissionKind: PermissionKind) {
        guard confirmOpenPrivacyPane(permissionKind) else { return }
        openPrivacyPane(permissionKind.settingsAnchor)
    }
}
