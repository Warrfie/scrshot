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
    static let knownBundleIdentifiers: Set<String> = [
        "io.github.Warrfie.scrshot",
        "io.github.Warrfie.scrshot.dev",
        "com.warrfie.scrshot",
    ]
    static let knownExecutableNames: Set<String> = [
        "scrshot",
        "scrshot-dev",
    ]

    struct RunningApp: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let bundlePath: String?
        let executablePath: String?
        let localizedName: String?

        init(
            processIdentifier: pid_t,
            bundleIdentifier: String? = nil,
            bundlePath: String? = nil,
            executablePath: String? = nil,
            localizedName: String? = nil
        ) {
            self.processIdentifier = processIdentifier
            self.bundleIdentifier = bundleIdentifier
            self.bundlePath = bundlePath
            self.executablePath = executablePath
            self.localizedName = localizedName
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
                    bundleIdentifier: $0.bundleIdentifier,
                    bundlePath: $0.bundleURL?.path,
                    executablePath: $0.executableURL?.path,
                    localizedName: $0.localizedName
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
        let nameMatches = runningApplicationsProvider(nil).filter(isKnownScrshotApplication)

        var seenProcessIdentifiers = Set<pid_t>()
        return (bundleMatches + nameMatches)
            .map(\.processIdentifier)
            .filter { $0 != currentProcessIdentifier }
            .filter { seenProcessIdentifiers.insert($0).inserted }
    }

    private func isKnownScrshotApplication(_ app: RunningApp) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier,
           Self.knownBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        if let executableName = app.executablePath.map({ URL(fileURLWithPath: $0).lastPathComponent }),
           Self.knownExecutableNames.contains(executableName) {
            return true
        }
        if let bundleName = app.bundlePath.map({ URL(fileURLWithPath: $0).lastPathComponent }),
           ["scrshot.app", "scrshot-dev.app"].contains(bundleName) {
            return true
        }
        if let localizedName = app.localizedName,
           Self.knownExecutableNames.contains(localizedName) {
            return true
        }
        return false
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
                AppLogger.shared.error(.appDiagnostics, "failed to build privacy pane URL anchor=\(anchor)")
                return
            }
            AppLogger.shared.info(.appDiagnostics, "opening privacy pane anchor=\(anchor)")
            NSWorkspace.shared.open(url)
        }
    ) {
        self.screenCapturePermissionController = screenCapturePermissionController
        self.microphonePermissionController = microphonePermissionController
        self.openPrivacyPane = openPrivacyPane
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
        _ = screenCapturePermissionController.requestAccessIfNeeded()
        if screenCapturePermissionController.hasAccess {
            return true
        }
        openPrivacyPane("Privacy_ScreenCapture")
        return false
    }

    func ensurePermissionsForRecording(audioSource: AppPreferences.RecordingAudioSource) async -> Bool {
        if !screenCapturePermissionController.hasAccess {
            _ = screenCapturePermissionController.requestAccessIfNeeded()
            if screenCapturePermissionController.hasAccess {
                return true
            }
            openPrivacyPane("Privacy_ScreenCapture")
            return false
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
