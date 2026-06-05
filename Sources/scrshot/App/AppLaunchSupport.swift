import AppKit
import AVFoundation
import Security

enum AppSceneID {
    static let about = "about"
}

enum XcodePreviewSupport {
    static let isRunning = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

struct AppInstanceCoordinator {
    static let disableSingleInstanceEnvironmentKey = "SCRSHOT_DISABLE_SINGLE_INSTANCE_ENFORCEMENT"

    struct RunningApp: Equatable {
        let processIdentifier: pid_t
    }

    let bundleIdentifier: String?
    let currentProcessIdentifier: pid_t
    let environment: [String: String]
    let runningApplicationsProvider: (String) -> [RunningApp]

    init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runningApplicationsProvider: @escaping (String) -> [RunningApp] = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .map { RunningApp(processIdentifier: $0.processIdentifier) }
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
        guard let bundleIdentifier else { return [] }
        return runningApplicationsProvider(bundleIdentifier)
            .map(\.processIdentifier)
            .filter { $0 != currentProcessIdentifier }
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
