import AppKit
import Foundation
import SwiftUI

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

@MainActor
final class AppMessageWindowController: NSWindowController, NSWindowDelegate {
    private static var activeControllers: [ObjectIdentifier: AppMessageWindowController] = [:]

    static func present(
        title: String,
        message: String,
        details: String? = nil,
        primaryButtonTitle: String? = nil,
        secondaryButtonTitle: String = "OK",
        onPrimary: (() -> Void)? = nil
    ) {
        let controller = AppMessageWindowController(
            title: title,
            message: message,
            details: details,
            primaryButtonTitle: primaryButtonTitle,
            secondaryButtonTitle: secondaryButtonTitle,
            onPrimary: onPrimary
        )
        let key = ObjectIdentifier(controller)
        activeControllers[key] = controller
        controller.onClose = {
            activeControllers.removeValue(forKey: key)
        }
        controller.show()
    }

    private var onClose: (() -> Void)?

    init(
        title: String,
        message: String,
        details: String?,
        primaryButtonTitle: String?,
        secondaryButtonTitle: String,
        onPrimary: (() -> Void)?
    ) {
        let contentView = AppMessageView(
            title: title,
            message: message,
            details: details,
            primaryButtonTitle: primaryButtonTitle,
            secondaryButtonTitle: secondaryButtonTitle,
            onPrimary: onPrimary
        )
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.toolbarStyle = .unifiedCompact
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}

private struct AppMessageView: View {
    let title: String
    let message: String
    let details: String?
    let primaryButtonTitle: String?
    let secondaryButtonTitle: String
    let onPrimary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.body)

            if let details, !details.isEmpty {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if let primaryButtonTitle {
                    Button(primaryButtonTitle) {
                        onPrimary?()
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.bordered)
                }
                Button(secondaryButtonTitle) {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 220)
    }
}

enum CrashAlertPresenter {
    @MainActor
    static func presentIfNeeded(didPreviousRunCrash: Bool, logFilePath: String) {
        guard didPreviousRunCrash else { return }

        AppMessageWindowController.present(
            title: "scrshot closed unexpectedly",
            message: "The previous launch did not finish cleanly. Check the log if the issue repeats.",
            details: "Log: \(logFilePath)",
            primaryButtonTitle: "Open Log",
            secondaryButtonTitle: "OK"
        ) {
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
