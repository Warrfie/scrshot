import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let preferencesWindowController: PreferencesWindowController
    private let onToggleRecording: () -> Void
    private let isRecordingProvider: () -> Bool
    private let recordingAudioSourceProvider: () -> AppPreferences.RecordingAudioSource
    private let onSelectRecordingAudioSource: (AppPreferences.RecordingAudioSource) -> Void
    private let statusItem: NSStatusItem
    private let recordingMenuItem = NSMenuItem(title: "", action: #selector(toggleRecording), keyEquivalent: "")
    private let recordingAudioMenuItem = NSMenuItem(title: "Recording Audio", action: nil, keyEquivalent: "")

    init(
        preferencesWindowController: PreferencesWindowController,
        onToggleRecording: @escaping () -> Void,
        isRecordingProvider: @escaping () -> Bool,
        recordingAudioSourceProvider: @escaping () -> AppPreferences.RecordingAudioSource,
        onSelectRecordingAudioSource: @escaping (AppPreferences.RecordingAudioSource) -> Void
    ) {
        self.preferencesWindowController = preferencesWindowController
        self.onToggleRecording = onToggleRecording
        self.isRecordingProvider = isRecordingProvider
        self.recordingAudioSourceProvider = recordingAudioSourceProvider
        self.onSelectRecordingAudioSource = onSelectRecordingAudioSource
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        applyStatusButtonAppearance(isRecording: false)

        let menu = NSMenu()
        menu.delegate = self
        let aboutItem = NSMenuItem(title: "About scrshot…", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        recordingMenuItem.target = self
        menu.addItem(recordingMenuItem)
        menu.addItem(recordingAudioMenuItem)

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit scrshot", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateRecordingMenuItem()
        configureRecordingAudioSubmenu()
    }

    private var versionMenuTitle: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(buildVersion))"
    }

    @objc
    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "scrshot"
        alert.informativeText = "\(versionMenuTitle)\nAuthor: warrfie\nGitHub: https://github.com/warrfie"
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            alert.icon = iconImage
        } else {
            alert.icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        }
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: "https://github.com/warrfie") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc
    private func openPreferences() {
        preferencesWindowController.show()
    }

    @objc
    private func toggleRecording() {
        onToggleRecording()
        updateRecordingMenuItem()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateRecordingMenuItem()
        updateRecordingAudioSubmenu()
    }

    func setRecordingState(_ isRecording: Bool) {
        applyStatusButtonAppearance(isRecording: isRecording)
        updateRecordingMenuItem()
    }

    private func updateRecordingMenuItem() {
        recordingMenuItem.title = isRecordingProvider() ? "Stop Screen Recording" : "Start Screen Recording"
    }

    private func configureRecordingAudioSubmenu() {
        let submenu = NSMenu()
        for source in AppPreferences.RecordingAudioSource.allCases {
            let item = NSMenuItem(title: source.title, action: #selector(selectRecordingAudioSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.rawValue
            submenu.addItem(item)
        }
        recordingAudioMenuItem.submenu = submenu
        updateRecordingAudioSubmenu()
    }

    private func updateRecordingAudioSubmenu() {
        guard let items = recordingAudioMenuItem.submenu?.items else { return }
        let selectedSource = recordingAudioSourceProvider()
        for item in items {
            let rawValue = item.representedObject as? String
            item.state = rawValue == selectedSource.rawValue ? .on : .off
        }
    }

    @objc
    private func selectRecordingAudioSource(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let source = AppPreferences.RecordingAudioSource(rawValue: rawValue) else {
            return
        }
        onSelectRecordingAudioSource(source)
        updateRecordingAudioSubmenu()
    }

    private func applyStatusButtonAppearance(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = isRecording ? "record.circle.fill" : "camera.viewfinder"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "scrshot")
        button.image?.isTemplate = !isRecording
        button.contentTintColor = isRecording ? .systemRed : nil
        button.toolTip = isRecording ? "scrshot is recording" : "scrshot"
    }
}
