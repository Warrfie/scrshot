import AVFoundation
import AppKit
import Foundation

extension Notification.Name {
    static let appPreferencesDidChange = Notification.Name("AppPreferences.didChange")
}

@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let theme = "theme"
        static let saveDirectoryPath = "saveDirectoryPath"
        static let launchAtLogin = "launchAtLogin"
        static let exportBehavior = "exportBehavior"
        static let fileNamePrefix = "fileNamePrefix"
        static let timestampTemplate = "timestampTemplate"
        static let revealSavedFile = "revealSavedFile"
        static let recordingAudioSource = "recordingAudioSource"
        static let recordingFileFormat = "recordingFileFormat"
    }

    enum Theme: String, CaseIterable {
        case system
        case light
        case dark

        var title: String {
            switch self {
            case .system:
                return "System"
            case .light:
                return "Light"
            case .dark:
                return "Dark"
            }
        }

        var appearance: NSAppearance? {
            switch self {
            case .system:
                return nil
            case .light:
                return NSAppearance(named: .aqua)
            case .dark:
                return NSAppearance(named: .darkAqua)
            }
        }
    }

    enum ExportBehavior: String, CaseIterable {
        case copyAndSave
        case copyOnly
        case saveOnly

        var title: String {
            switch self {
            case .copyAndSave:
                return "Copy and Save"
            case .copyOnly:
                return "Copy Only"
            case .saveOnly:
                return "Save Only"
            }
        }
    }

    enum RecordingAudioSource: String, CaseIterable {
        case systemAudio
        case noAudio
        case microphoneOnly
        case systemAudioAndMicrophone

        var title: String {
            switch self {
            case .systemAudio:
                return "System Audio"
            case .noAudio:
                return "No Audio"
            case .microphoneOnly:
                return "Microphone Only"
            case .systemAudioAndMicrophone:
                return "System + Microphone"
            }
        }

        var capturesSystemAudio: Bool {
            self == .systemAudio || self == .systemAudioAndMicrophone
        }

        var capturesMicrophone: Bool {
            self == .microphoneOnly || self == .systemAudioAndMicrophone
        }
    }

    enum RecordingFileFormat: String, CaseIterable {
        case mov
        case mp4

        var title: String {
            switch self {
            case .mov:
                return "MOV"
            case .mp4:
                return "MP4"
            }
        }

        var fileType: AVFileType {
            switch self {
            case .mov:
                return .mov
            case .mp4:
                return .mp4
            }
        }

        var fileExtension: String {
            switch self {
            case .mov:
                return "mov"
            case .mp4:
                return "mp4"
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.hotkeyKeyCode: Int(HotkeyManager.defaultCaptureHotkey.keyCode),
            Keys.hotkeyModifiers: Int(HotkeyManager.defaultCaptureHotkey.modifiers),
            Keys.theme: Theme.system.rawValue,
            Keys.saveDirectoryPath: Self.defaultSaveDirectoryURL.path,
            Keys.launchAtLogin: false,
            Keys.exportBehavior: ExportBehavior.copyAndSave.rawValue,
            Keys.fileNamePrefix: "screenshot",
            Keys.timestampTemplate: "yyyy-MM-dd_HH-mm-ss",
            Keys.revealSavedFile: false,
            Keys.recordingAudioSource: RecordingAudioSource.systemAudio.rawValue,
            Keys.recordingFileFormat: RecordingFileFormat.mov.rawValue,
        ])
    }

    var captureHotkey: HotkeyManager.HotkeyDescriptor {
        get {
            let keyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int ?? Int(HotkeyManager.defaultCaptureHotkey.keyCode)
            let modifiers = defaults.object(forKey: Keys.hotkeyModifiers) as? Int ?? Int(HotkeyManager.defaultCaptureHotkey.modifiers)
            return HotkeyManager.HotkeyDescriptor(
                id: HotkeyManager.defaultCaptureHotkey.id,
                keyCode: UInt32(keyCode),
                modifiers: UInt32(modifiers)
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Keys.hotkeyKeyCode)
            defaults.set(Int(newValue.modifiers), forKey: Keys.hotkeyModifiers)
            notifyChange()
        }
    }

    var theme: Theme {
        get {
            let rawValue = defaults.string(forKey: Keys.theme) ?? Theme.system.rawValue
            return Theme(rawValue: rawValue) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.theme)
            notifyChange()
        }
    }

    var saveDirectoryURL: URL {
        get {
            let path = defaults.string(forKey: Keys.saveDirectoryPath) ?? Self.defaultSaveDirectoryURL.path
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            defaults.set(newValue.path, forKey: Keys.saveDirectoryPath)
            notifyChange()
        }
    }

    var launchAtLogin: Bool {
        get {
            defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            notifyChange()
        }
    }

    var exportBehavior: ExportBehavior {
        get {
            let rawValue = defaults.string(forKey: Keys.exportBehavior) ?? ExportBehavior.copyAndSave.rawValue
            return ExportBehavior(rawValue: rawValue) ?? .copyAndSave
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.exportBehavior)
            notifyChange()
        }
    }

    var fileNamePrefix: String {
        get {
            let value = defaults.string(forKey: Keys.fileNamePrefix) ?? "screenshot"
            return Self.sanitizedPrefix(value)
        }
        set {
            defaults.set(Self.sanitizedPrefix(newValue), forKey: Keys.fileNamePrefix)
            notifyChange()
        }
    }

    var timestampTemplate: String {
        get {
            let value = defaults.string(forKey: Keys.timestampTemplate) ?? "yyyy-MM-dd_HH-mm-ss"
            return value.isEmpty ? "yyyy-MM-dd_HH-mm-ss" : value
        }
        set {
            let sanitized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(sanitized.isEmpty ? "yyyy-MM-dd_HH-mm-ss" : sanitized, forKey: Keys.timestampTemplate)
            notifyChange()
        }
    }

    var revealSavedFile: Bool {
        get {
            defaults.object(forKey: Keys.revealSavedFile) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Keys.revealSavedFile)
            notifyChange()
        }
    }

    var recordingAudioSource: RecordingAudioSource {
        get {
            let rawValue = defaults.string(forKey: Keys.recordingAudioSource) ?? RecordingAudioSource.systemAudio.rawValue
            return RecordingAudioSource(rawValue: rawValue) ?? .systemAudio
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.recordingAudioSource)
            notifyChange()
        }
    }

    var recordingFileFormat: RecordingFileFormat {
        get {
            let rawValue = defaults.string(forKey: Keys.recordingFileFormat) ?? RecordingFileFormat.mov.rawValue
            return RecordingFileFormat(rawValue: rawValue) ?? .mov
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.recordingFileFormat)
            notifyChange()
        }
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.hotkeyKeyCode)
        defaults.removeObject(forKey: Keys.hotkeyModifiers)
        defaults.removeObject(forKey: Keys.theme)
        defaults.removeObject(forKey: Keys.saveDirectoryPath)
        defaults.removeObject(forKey: Keys.launchAtLogin)
        defaults.removeObject(forKey: Keys.exportBehavior)
        defaults.removeObject(forKey: Keys.fileNamePrefix)
        defaults.removeObject(forKey: Keys.timestampTemplate)
        defaults.removeObject(forKey: Keys.revealSavedFile)
        defaults.removeObject(forKey: Keys.recordingAudioSource)
        defaults.removeObject(forKey: Keys.recordingFileFormat)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .appPreferencesDidChange, object: self)
    }

    private static var defaultSaveDirectoryURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Screenshots", isDirectory: true)
    }

    private static func sanitizedPrefix(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(
            of: #"[\\/:*?"<>|]+"#,
            with: "-",
            options: .regularExpression
        )
        return sanitized.isEmpty ? "screenshot" : sanitized
    }
}
