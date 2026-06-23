import AppKit
import SwiftUI

@MainActor
final class StatusItemController: ObservableObject {
    static let shared = StatusItemController()

    @Published private(set) var isRecording = false
    @Published private(set) var recordingAudioSource: AppPreferences.RecordingAudioSource = .noAudio

    private var onToggleRecording: (() -> Void)?
    private var onSelectRecordingAudioSource: ((AppPreferences.RecordingAudioSource) -> Void)?

    private init() {}

    func configure(
        onToggleRecording: @escaping () -> Void,
        isRecordingProvider: @escaping () -> Bool,
        recordingAudioSourceProvider: @escaping () -> AppPreferences.RecordingAudioSource,
        onSelectRecordingAudioSource: @escaping (AppPreferences.RecordingAudioSource) -> Void
    ) {
        self.onToggleRecording = onToggleRecording
        self.onSelectRecordingAudioSource = onSelectRecordingAudioSource
        self.isRecording = isRecordingProvider()
        self.recordingAudioSource = recordingAudioSourceProvider()
    }

    var versionMenuTitle: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3"
        return "Version \(shortVersion)"
    }

    var menuBarSymbolName: String {
        isRecording ? "record.circle.fill" : "camera.viewfinder"
    }

    var recordingMenuTitle: String {
        isRecording ? "Stop Screen Recording" : "Start Screen Recording"
    }

    func toggleRecording() {
        onToggleRecording?()
    }

    func selectRecordingAudioSource(_ source: AppPreferences.RecordingAudioSource) {
        recordingAudioSource = source
        onSelectRecordingAudioSource?(source)
    }

    func setRecordingState(_ isRecording: Bool) {
        self.isRecording = isRecording
    }

    func refreshRecordingAudioSource(_ source: AppPreferences.RecordingAudioSource) {
        recordingAudioSource = source
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

struct StatusItemMenuBarContent: View {
    @ObservedObject var controller: StatusItemController

    var body: some View {
        VStack {
            Button("About scrshot…") {
                AboutWindowPresenter.show()
            }

            Divider()

            Button(controller.recordingMenuTitle) {
                controller.toggleRecording()
            }

            Picker("Recording Audio", selection: Binding(
                get: { controller.recordingAudioSource },
                set: { controller.selectRecordingAudioSource($0) }
            )) {
                ForEach(AppPreferences.RecordingAudioSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }

            Button("Preferences…") {
                SettingsWindowPresenter.show()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Quit scrshot") {
                controller.quit()
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
