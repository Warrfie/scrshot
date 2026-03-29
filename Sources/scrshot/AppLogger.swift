import Foundation

enum AppLogLevel {
    case debug
    case info
    case error
}

enum AppLogCategory: String {
    case appLifecycle = "AppLifecycle"
    case appDiagnostics = "AppDiagnostics"
    case appCoordinator = "AppCoordinator"
    case screenCaptureService = "ScreenCaptureService"
    case screenRecordingService = "ScreenRecordingService"
    case editorWindow = "EditorWindow"
    case editorFit = "EditorFit"
    case hotkey = "Hotkey"
}

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.warrfie.scrshot.logger")
    private let logFileURL: URL

    private init() {
        let directory: URL
        if let logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("scrshot", isDirectory: true) {
            directory = logsDirectory
        } else {
            directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scrshot-logs", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logFileURL = directory.appendingPathComponent("latest.log")
        let header = "\n---- launch \(ISO8601DateFormatter().string(from: Date())) ----\n"
        if let data = header.data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: data)
            } else if let handle = try? FileHandle(forWritingTo: logFileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        }
    }

    var currentLogFilePath: String {
        logFileURL.path
    }

    func log(_ message: String) {
        NSLog("%@", message)
        let line = "\(timestamp()) \(message)\n"
        queue.async { [logFileURL] in
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        switch level {
        case .debug:
            debug("[\(category.rawValue)] \(message)")
        case .info, .error:
            log("[\(category.rawValue)] \(message)")
        }
    }

    func debug(_ message: String) {
#if DEBUG
        log(message)
#endif
    }

    func debug(_ category: AppLogCategory, _ message: String) {
        log(.debug, category: category, message)
    }

    func info(_ category: AppLogCategory, _ message: String) {
        log(.info, category: category, message)
    }

    func error(_ category: AppLogCategory, _ message: String) {
        log(.error, category: category, message)
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
