import AppKit
import Foundation

protocol SoundPlayback {
    @discardableResult
    func play() -> Bool
}

extension NSSound: SoundPlayback {}

@MainActor
final class AppTerminationStateTracker {
    enum Keys {
        static let lastRunEndedCleanly = "app.lastRunEndedCleanly"
        static let lastLaunchTimestamp = "app.lastLaunchTimestamp"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markLaunchStarted(now: Date = Date()) -> Bool {
        let endedCleanly = defaults.object(forKey: Keys.lastRunEndedCleanly) as? Bool ?? true
        defaults.set(false, forKey: Keys.lastRunEndedCleanly)
        defaults.set(now.timeIntervalSince1970, forKey: Keys.lastLaunchTimestamp)
        return !endedCleanly
    }

    func markTerminatedCleanly() {
        defaults.set(true, forKey: Keys.lastRunEndedCleanly)
    }
}

@MainActor
final class CaptureSoundPlayer {
    private let namedSoundProvider: (NSSound.Name) -> SoundPlayback?
    private let beepPlayer: () -> Void

    init(
        namedSoundProvider: @escaping (NSSound.Name) -> SoundPlayback? = { NSSound(named: $0) },
        beepPlayer: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.namedSoundProvider = namedSoundProvider
        self.beepPlayer = beepPlayer
    }

    @discardableResult
    func playCaptureSoundIfEnabled(preferences: AppPreferences) -> Bool {
        guard preferences.playsCaptureSound else {
            return false
        }
        if let soundName = preferences.captureSound.soundName {
            if let sound = namedSoundProvider(soundName) {
                sound.play()
                return true
            }
        } else {
            beepPlayer()
            return true
        }
        beepPlayer()
        return true
    }
}

enum CrashAlertPresenter {
    @MainActor
    static func presentIfNeeded(didPreviousRunCrash: Bool, logFilePath: String) {
        guard didPreviousRunCrash else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "scrshot closed unexpectedly"
        alert.informativeText = "The previous launch did not finish cleanly. Check the log if the issue repeats.\n\nLog: \(logFilePath)"
        alert.addButton(withTitle: "Open Log")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: logFilePath))
        }
    }
}

enum AppCrashMonitor {
    static func installUncaughtExceptionLogger() {
        NSSetUncaughtExceptionHandler { exception in
            let stackTrace = exception.callStackSymbols.joined(separator: "\n")
            AppLogger.shared.error(
                .appDiagnostics,
                "uncaught exception name=\(exception.name.rawValue) reason=\(exception.reason ?? "unknown")\n\(stackTrace)"
            )
        }
    }
}
