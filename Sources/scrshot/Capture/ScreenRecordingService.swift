import AVFoundation
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenRecordingService: NSObject {
    enum RecordingError: LocalizedError {
        case screenRecordingPermissionDenied
        case screenUnavailable
        case unsupportedSystemVersion
        case failedToStartCapture
        case failedToFinalize
        case recordingFailed(String)

        var errorDescription: String? {
            switch self {
            case .screenRecordingPermissionDenied:
                return "Screen Recording permission is required."
            case .screenUnavailable:
                return "Unable to find the current display for recording."
            case .unsupportedSystemVersion:
                return "Video recording requires macOS 15 or newer."
            case .failedToStartCapture:
                return "Unable to start screen recording."
            case .failedToFinalize:
                return "Unable to finalize the recorded video file."
            case let .recordingFailed(message):
                return message
            }
        }
    }

    struct RecordingOptions {
        let directory: URL
        let fileNamePrefix: String
        let timestampTemplate: String
        let audioSource: AppPreferences.RecordingAudioSource
        let fileFormat: AppPreferences.RecordingFileFormat
    }

    private var nativeSession: AnyObject?
    private(set) var isRecording = false
    var onRecordingStateChanged: ((Bool) -> Void)?
    private let permissionController: ScreenCapturePermissionController

    init(permissionController: ScreenCapturePermissionController = .shared) {
        self.permissionController = permissionController
    }

    func startRecording(options: RecordingOptions) async throws -> URL {
        guard !isRecording else {
            throw RecordingError.failedToStartCapture
        }

        guard permissionController.hasAccess else {
            _ = permissionController.requestAccessIfNeeded()
            throw RecordingError.screenRecordingPermissionDenied
        }

        let selection = try await currentDisplaySelection()
        let targetURL = try prepareOutputURL(options: options)
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw RecordingError.screenUnavailable
        }

        guard #available(macOS 15.0, *) else {
            throw RecordingError.unsupportedSystemVersion
        }

        let session = NativeRecordingSession(
            display: display,
            scaleFactor: selection.screen.backingScaleFactor,
            outputURL: targetURL,
            audioSource: options.audioSource,
            fileFormat: options.fileFormat,
            onStateChanged: { [weak self] isRecording in
                self?.isRecording = isRecording
                self?.onRecordingStateChanged?(isRecording)
            }
        )
        nativeSession = session

        do {
            return try await session.start()
        } catch {
            nativeSession = nil
            isRecording = false
            onRecordingStateChanged?(false)
            throw error
        }
    }

    func stopRecording() async throws -> URL {
        guard #available(macOS 15.0, *),
              let session = nativeSession as? NativeRecordingSession else {
            nativeSession = nil
            isRecording = false
            onRecordingStateChanged?(false)
            throw RecordingError.failedToFinalize
        }

        defer {
            nativeSession = nil
            isRecording = false
            onRecordingStateChanged?(false)
        }

        do {
            return try await session.stop()
        } catch {
            throw error
        }
    }

    private func currentDisplaySelection() async throws -> (screen: NSScreen, displayID: CGDirectDisplayID) {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? screens.first,
              let displayID = screen.displayID else {
            throw RecordingError.screenUnavailable
        }
        return (screen, displayID)
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: error ?? RecordingError.screenUnavailable)
                }
            }
        }
    }

    private func prepareOutputURL(options: RecordingOptions) throws -> URL {
        try FileManager.default.createDirectory(at: options.directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = options.timestampTemplate.isEmpty ? "yyyy-MM-dd_HH-mm-ss" : options.timestampTemplate

        let prefix = sanitizedPrefix(options.fileNamePrefix)
        let fileName = "\(prefix)_recording_\(formatter.string(from: Date())).\(options.fileFormat.fileExtension)"
        return options.directory.appendingPathComponent(fileName)
    }

    private func sanitizedPrefix(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(of: #"[\\/:*?"<>|]+"#, with: "-", options: .regularExpression)
        return sanitized.isEmpty ? "screenshot" : sanitized
    }
}

@available(macOS 15.0, *)
private final class NativeRecordingSession: NSObject {
    private let display: SCDisplay
    private let scaleFactor: CGFloat
    private let outputURL: URL
    private let audioSource: AppPreferences.RecordingAudioSource
    private let fileFormat: AppPreferences.RecordingFileFormat
    private let onStateChanged: (Bool) -> Void
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var finishContinuation: CheckedContinuation<URL, Error>?
    private var pendingError: Error?
    private var didStartRecording = false

    init(
        display: SCDisplay,
        scaleFactor: CGFloat,
        outputURL: URL,
        audioSource: AppPreferences.RecordingAudioSource,
        fileFormat: AppPreferences.RecordingFileFormat,
        onStateChanged: @escaping (Bool) -> Void
    ) {
        self.display = display
        self.scaleFactor = scaleFactor
        self.outputURL = outputURL
        self.audioSource = audioSource
        self.fileFormat = fileFormat
        self.onStateChanged = onStateChanged
    }

    func start() async throws -> URL {
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int(display.frame.width * scaleFactor))
        configuration.height = max(2, Int(display.frame.height * scaleFactor))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = true
        configuration.capturesAudio = audioSource.capturesSystemAudio
        configuration.captureMicrophone = audioSource.capturesMicrophone
        configuration.queueDepth = 8

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.videoCodecType = .h264
        recordingConfiguration.outputFileType = fileFormat.fileType

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)

        do {
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
        } catch {
            teardown()
            AppLogger.shared.error(.screenRecordingService, "native recording start failed: \(error.localizedDescription)")
            throw ScreenRecordingService.RecordingError.failedToStartCapture
        }

        self.stream = stream
        self.recordingOutput = recordingOutput

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    func stop() async throws -> URL {
        guard let stream else {
            throw ScreenRecordingService.RecordingError.failedToFinalize
        }

        onStateChanged(false)

        do {
            try await stream.stopCapture()
        } catch {
            teardown()
            AppLogger.shared.error(.screenRecordingService, "native recording stop failed: \(error.localizedDescription)")
            throw ScreenRecordingService.RecordingError.failedToFinalize
        }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation

            if let pendingError {
                self.pendingError = nil
                finishContinuation = nil
                continuation.resume(throwing: mapError(pendingError))
                return
            }

            if recordingOutput == nil, didStartRecording {
                finishContinuation = nil
                continuation.resume(returning: outputURL)
            }
        }
    }

    private func mapError(_ error: Error) -> Error {
        if let recordingError = error as? ScreenRecordingService.RecordingError {
            return recordingError
        }
        return ScreenRecordingService.RecordingError.recordingFailed(error.localizedDescription)
    }

    private func teardown() {
        stream = nil
        recordingOutput = nil
    }
}

@available(macOS 15.0, *)
extension NativeRecordingSession: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            AppLogger.shared.error(.screenRecordingService, "native stream stopped with error: \(error.localizedDescription)")
            self.pendingError = error
            self.onStateChanged(false)

            if let startContinuation = self.startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: self.mapError(error))
            }

            if let finishContinuation = self.finishContinuation {
                self.finishContinuation = nil
                finishContinuation.resume(throwing: self.mapError(error))
            }

            self.teardown()
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.didStartRecording = true
            self.onStateChanged(true)
            AppLogger.shared.info(.screenRecordingService, "recording started format=\(self.outputURL.pathExtension.lowercased())")
            self.startContinuation?.resume(returning: self.outputURL)
            self.startContinuation = nil
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            AppLogger.shared.error(.screenRecordingService, "native recording output failed: \(error.localizedDescription)")
            self.pendingError = error
            self.onStateChanged(false)

            if let startContinuation = self.startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: self.mapError(error))
            }

            if let finishContinuation = self.finishContinuation {
                self.finishContinuation = nil
                finishContinuation.resume(throwing: self.mapError(error))
            }

            self.teardown()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            AppLogger.shared.info(.screenRecordingService, "recording finished format=\(self.outputURL.pathExtension.lowercased())")
            self.onStateChanged(false)
            self.finishContinuation?.resume(returning: self.outputURL)
            self.finishContinuation = nil
            self.teardown()
        }
    }
}
