import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let hostingController: NSHostingController<PreferencesSceneView>
    private var resignKeyObserver: NSObjectProtocol?

    init(preferences: AppPreferences) {
        self.hostingController = NSHostingController(rootView: PreferencesSceneView(preferences: preferences))

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.toolbarStyle = .preference
        super.init(window: window)
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeIfResignedWithoutModalWindow()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
    }

    func show() {
        showWindow(nil)
        window?.centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        window?.recenterOnActiveScreenAfterLayout()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeIfResignedWithoutModalWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.isVisible else { return }
            guard window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
            window.close()
        }
    }
}

@MainActor
enum SettingsWindowPresenter {
    static var showHandler: (() -> Void)?

    static func show() {
        guard !XcodePreviewSupport.isRunning else { return }
        if let showHandler {
            showHandler()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

@MainActor
struct PreferencesSceneView: View {
    @StateObject private var viewModel: PreferencesViewModel

    init(preferences: AppPreferences) {
        _viewModel = StateObject(wrappedValue: PreferencesViewModel(preferences: preferences))
    }

    var body: some View {
        PreferencesRootView(viewModel: viewModel)
    }
}

@MainActor
final class PreferencesViewModel: ObservableObject {
    @Published private(set) var permissionSnapshot: PermissionStatusSnapshot = .current()

    let preferences: AppPreferences

    private var observer: NSObjectProtocol?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.observer = NotificationCenter.default.addObserver(
            forName: .appPreferencesDidChange,
            object: preferences,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatus()
                self?.objectWillChange.send()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var captureHotkey: HotkeyManager.HotkeyDescriptor {
        get { preferences.captureHotkey }
        set { preferences.captureHotkey = newValue }
    }

    var saveDirectoryDescription: String {
        preferences.selectedSaveDirectoryURL?.path ?? "Not selected"
    }

    var canRevealSaveDirectory: Bool {
        preferences.hasSaveDirectoryBookmark
    }

    var theme: AppPreferences.Theme {
        get { preferences.theme }
        set { preferences.theme = newValue }
    }

    var exportBehavior: AppPreferences.ExportBehavior {
        get { preferences.exportBehavior }
        set { preferences.exportBehavior = newValue }
    }

    var recordingFormat: AppPreferences.RecordingFileFormat {
        get { preferences.recordingFileFormat }
        set { preferences.recordingFileFormat = newValue }
    }

    var fileNamePrefix: String {
        get { preferences.fileNamePrefix }
        set { preferences.fileNamePrefix = newValue }
    }

    var timestampTemplate: String {
        get { preferences.timestampTemplate }
        set { preferences.timestampTemplate = newValue }
    }

    var launchAtLogin: Bool {
        get { preferences.launchAtLogin }
        set { preferences.launchAtLogin = newValue }
    }

    var revealSavedFile: Bool {
        get { preferences.revealSavedFile }
        set { preferences.revealSavedFile = newValue }
    }

    var playsCaptureSound: Bool {
        get { preferences.playsCaptureSound }
        set { preferences.playsCaptureSound = newValue }
    }

    var captureSound: AppPreferences.CaptureSound {
        get { preferences.captureSound }
        set { preferences.captureSound = newValue }
    }

    var screenCaptureSummary: String {
        permissionSnapshot.screenCaptureSummary
    }

    var microphoneSummary: String {
        permissionSnapshot.microphoneSummary
    }

    var screenCaptureColor: Color {
        permissionSnapshot.screenCaptureGranted ? .green : .red
    }

    var microphoneColor: Color {
        switch permissionSnapshot.microphoneStatus {
        case .authorized:
            return .green
        case .notDetermined:
            return .secondary
        case .denied, .restricted:
            return .red
        @unknown default:
            return .secondary
        }
    }

    var needsScreenCaptureAccess: Bool {
        !permissionSnapshot.screenCaptureGranted
    }

    var needsMicrophoneAccess: Bool {
        permissionSnapshot.microphoneStatus != .authorized
    }

    func updateSaveDirectory(_ url: URL) {
        do {
            try preferences.updateSaveDirectory(url)
            objectWillChange.send()
        } catch {
            AppLogger.shared.error(.preferences, "failed to update save directory: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    func revealFolder() {
        do {
            _ = try preferences.withSaveDirectoryAccess { directory in
                NSWorkspace.shared.open(directory)
            }
        } catch {
            AppLogger.shared.error(.preferences, "failed to reveal save directory: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    func refreshPermissionStatus() {
        permissionSnapshot = .current()
    }

    func resetToDefaults() {
        preferences.resetToDefaults()
        refreshPermissionStatus()
        objectWillChange.send()
    }

    func openScreenRecordingSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    func openMicrophoneSettings() {
        openPrivacyPane(anchor: "Privacy_Microphone")
    }

    func requestScreenRecordingAccess() {
        _ = ScreenCapturePermissionController.shared.requestAccessIfNeeded()
        refreshPermissionStatus()
        if needsScreenCaptureAccess {
            openScreenRecordingSettings()
        }
    }

    func requestMicrophoneAccess() {
        Task { @MainActor in
            _ = await MicrophonePermissionController.shared.requestAccessIfNeeded()
            refreshPermissionStatus()
            if needsMicrophoneAccess {
                openMicrophoneSettings()
            }
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

struct PreferencesRootView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var isChoosingSaveDirectory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Capture") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Shortcut") {
                            shortcutRecorderControl
                        }

                        LabeledContent("Save Folder") {
                            HStack(spacing: 10) {
                                Text(viewModel.saveDirectoryDescription)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .frame(minWidth: 320, alignment: .leading)
                                Button("Choose…") {
                                    isChoosingSaveDirectory = true
                                }
                                Button("Reveal") {
                                    viewModel.revealFolder()
                                }
                                .disabled(!viewModel.canRevealSaveDirectory)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Appearance") {
                    LabeledContent("Theme") {
                        Picker("Theme", selection: Binding(
                            get: { viewModel.theme },
                            set: { viewModel.theme = $0 }
                        )) {
                            ForEach(AppPreferences.Theme.allCases, id: \.self) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .frame(width: 180)
                        .labelsHidden()
                    }
                }

                GroupBox("Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Behavior") {
                            Picker("Behavior", selection: Binding(
                                get: { viewModel.exportBehavior },
                                set: { viewModel.exportBehavior = $0 }
                            )) {
                                ForEach(AppPreferences.ExportBehavior.allCases, id: \.self) { behavior in
                                    Text(behavior.title).tag(behavior)
                                }
                            }
                            .frame(width: 180)
                            .labelsHidden()
                        }

                        LabeledContent("Recording Format") {
                            Picker("Recording Format", selection: Binding(
                                get: { viewModel.recordingFormat },
                                set: { viewModel.recordingFormat = $0 }
                            )) {
                                ForEach(AppPreferences.RecordingFileFormat.allCases, id: \.self) { format in
                                    Text(format.title).tag(format)
                                }
                            }
                            .frame(width: 120)
                            .labelsHidden()
                        }

                        LabeledContent("File Prefix") {
                            TextField(
                                "screenshot",
                                text: Binding(
                                    get: { viewModel.fileNamePrefix },
                                    set: { viewModel.fileNamePrefix = $0 }
                                )
                            )
                            .frame(width: 280)
                        }

                        LabeledContent("Timestamp Template") {
                            TextField(
                                "yyyy-MM-dd_HH-mm-ss",
                                text: Binding(
                                    get: { viewModel.timestampTemplate },
                                    set: { viewModel.timestampTemplate = $0 }
                                )
                            )
                            .frame(width: 280)
                        }

                        Toggle("Reveal saved file in Finder after export", isOn: Binding(
                            get: { viewModel.revealSavedFile },
                            set: { viewModel.revealSavedFile = $0 }
                        ))

                        HStack(spacing: 10) {
                            Toggle("Play shutter sound after capture", isOn: Binding(
                                get: { viewModel.playsCaptureSound },
                                set: { viewModel.playsCaptureSound = $0 }
                            ))
                            Picker("Capture Sound", selection: Binding(
                                get: { viewModel.captureSound },
                                set: { viewModel.captureSound = $0 }
                            )) {
                                ForEach(AppPreferences.CaptureSound.allCases, id: \.self) { sound in
                                    Text(sound.title).tag(sound)
                                }
                            }
                            .frame(width: 180)
                            .disabled(!viewModel.playsCaptureSound)
                            .labelsHidden()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Startup") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.launchAtLogin = $0 }
                    ))
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(
                            title: "Screen Recording",
                            value: viewModel.screenCaptureSummary,
                            color: viewModel.screenCaptureColor,
                            showsRequestAction: viewModel.needsScreenCaptureAccess,
                            requestAction: viewModel.requestScreenRecordingAccess,
                            settingsAction: viewModel.openScreenRecordingSettings
                        )

                        permissionRow(
                            title: "Microphone",
                            value: viewModel.microphoneSummary,
                            color: viewModel.microphoneColor,
                            showsRequestAction: viewModel.needsMicrophoneAccess,
                            requestAction: viewModel.requestMicrophoneAccess,
                            settingsAction: viewModel.openMicrophoneSettings
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Text("Use Unicode date patterns like `yyyy-MM-dd_HH-mm-ss`. Export mode controls whether Done copies, saves, or does both.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Reset to Defaults") {
                        viewModel.resetToDefaults()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 700, minHeight: 560)
        .onAppear {
            viewModel.refreshPermissionStatus()
        }
        .fileImporter(
            isPresented: $isChoosingSaveDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                return
            }
            viewModel.updateSaveDirectory(url)
        }
    }

    private func permissionRow(
        title: String,
        value: String,
        color: Color,
        showsRequestAction: Bool,
        requestAction: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
                .frame(width: 140, alignment: .leading)
            if showsRequestAction {
                Button("Request Access", action: requestAction)
            }
            Button("Open Settings", action: settingsAction)
        }
    }

    @ViewBuilder
    private var shortcutRecorderControl: some View {
        if XcodePreviewSupport.isRunning {
            Text("Shift + 1")
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 220, alignment: .leading)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ShortcutRecorderRepresentable(
                descriptor: Binding(
                    get: { viewModel.captureHotkey },
                    set: { viewModel.captureHotkey = $0 }
                )
            )
            .frame(width: 220)
        }
    }
}

#if DEBUG
struct PreferencesSceneView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesSceneView(preferences: AppPreferences(defaults: UserDefaults(suiteName: "PreferencesPreview")!))
    }
}
#endif

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var descriptor: HotkeyManager.HotkeyDescriptor

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.descriptor = descriptor
        button.onChange = { newDescriptor in
            descriptor = newDescriptor
        }
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        if nsView.descriptor.keyCode != descriptor.keyCode || nsView.descriptor.modifiers != descriptor.modifiers {
            nsView.descriptor = descriptor
        }
        nsView.onChange = { newDescriptor in
            descriptor = newDescriptor
        }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var descriptor = HotkeyManager.defaultCaptureHotkey {
        didSet { updateTitle() }
    }
    var onChange: ((HotkeyManager.HotkeyDescriptor) -> Void)?

    private var isRecording = false {
        didSet { updateTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        focusRingType = .default
        updateTitle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    @objc
    private func beginRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Self.carbonModifiers(from: modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }

        let descriptor = HotkeyManager.HotkeyDescriptor(
            id: HotkeyManager.defaultCaptureHotkey.id,
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        self.descriptor = descriptor
        onChange?(descriptor)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    private func updateTitle() {
        title = isRecording ? "Press shortcut…" : HotkeyFormatter.string(for: descriptor)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }
}
