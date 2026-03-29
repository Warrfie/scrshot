import AppKit
import Carbon

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let preferences: AppPreferences
    private let preferencesContentViewController: NSViewController

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.preferencesContentViewController = PreferencesViewController(preferences: preferences)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = preferencesContentViewController
        window.toolbarStyle = .preference
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class PreferencesViewController: NSViewController, NSTextFieldDelegate {
    private let preferences: AppPreferences
    private let shortcutRecorderButton = ShortcutRecorderButton()
    private let saveLocationControl = NSPathControl()
    private let themePopupButton = NSPopUpButton()
    private let exportBehaviorPopupButton = NSPopUpButton()
    private let recordingFormatPopupButton = NSPopUpButton()
    private let fileNamePrefixField = NSTextField()
    private let timestampTemplateField = NSTextField()
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let revealSavedFileButton = NSButton(checkboxWithTitle: "Reveal saved file in Finder after export", target: nil, action: nil)

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeSectionLabel("Capture Shortcut")
        let folderLabel = makeSectionLabel("Save Folder")
        let themeLabel = makeSectionLabel("Theme")
        let launchLabel = makeSectionLabel("Startup")
        let exportModeLabel = makeSectionLabel("Export")
        let recordingFormatLabel = makeSectionLabel("Recording Format")
        let fileNamePrefixLabel = makeSectionLabel("File Prefix")
        let timestampTemplateLabel = makeSectionLabel("Timestamp Template")
        let noteLabel = NSTextField(labelWithString: "Use Unicode date patterns like yyyy-MM-dd_HH-mm-ss. Export mode controls whether Done copies, saves, or does both.")
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.maximumNumberOfLines = 0

        shortcutRecorderButton.onChange = { [weak self] descriptor in
            self?.preferences.captureHotkey = descriptor
        }

        let chooseFolderButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseFolderButton.bezelStyle = .rounded
        let revealFolderButton = NSButton(title: "Reveal", target: self, action: #selector(revealFolder))
        revealFolderButton.bezelStyle = .rounded

        saveLocationControl.isEditable = false
        saveLocationControl.pathStyle = .popUp

        for theme in AppPreferences.Theme.allCases {
            themePopupButton.addItem(withTitle: theme.title)
            themePopupButton.lastItem?.representedObject = theme
        }
        themePopupButton.target = self
        themePopupButton.action = #selector(themeChanged(_:))

        for behavior in AppPreferences.ExportBehavior.allCases {
            exportBehaviorPopupButton.addItem(withTitle: behavior.title)
            exportBehaviorPopupButton.lastItem?.representedObject = behavior
        }
        exportBehaviorPopupButton.target = self
        exportBehaviorPopupButton.action = #selector(exportBehaviorChanged(_:))

        for format in AppPreferences.RecordingFileFormat.allCases {
            recordingFormatPopupButton.addItem(withTitle: format.title)
            recordingFormatPopupButton.lastItem?.representedObject = format
        }
        recordingFormatPopupButton.target = self
        recordingFormatPopupButton.action = #selector(recordingFormatChanged(_:))

        fileNamePrefixField.placeholderString = "screenshot"
        fileNamePrefixField.delegate = self
        fileNamePrefixField.target = self
        fileNamePrefixField.action = #selector(fileNamePrefixChanged(_:))

        timestampTemplateField.placeholderString = "yyyy-MM-dd_HH-mm-ss"
        timestampTemplateField.delegate = self
        timestampTemplateField.target = self
        timestampTemplateField.action = #selector(timestampTemplateChanged(_:))

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged(_:))

        revealSavedFileButton.target = self
        revealSavedFileButton.action = #selector(revealSavedFileChanged(_:))

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded

        let shortcutRow = makeRow(label: titleLabel, mainView: shortcutRecorderButton, trailingView: nil)
        let folderRow = makeRow(label: folderLabel, mainView: saveLocationControl, trailingViews: [chooseFolderButton, revealFolderButton])
        let themeRow = makeRow(label: themeLabel, mainView: themePopupButton, trailingView: nil)
        let launchRow = makeRow(label: launchLabel, mainView: launchAtLoginButton, trailingView: nil)
        let exportModeRow = makeRow(label: exportModeLabel, mainView: exportBehaviorPopupButton, trailingView: nil)
        let recordingFormatRow = makeRow(label: recordingFormatLabel, mainView: recordingFormatPopupButton, trailingView: nil)
        let fileNamePrefixRow = makeRow(label: fileNamePrefixLabel, mainView: fileNamePrefixField, trailingView: nil)
        let timestampTemplateRow = makeRow(label: timestampTemplateLabel, mainView: timestampTemplateField, trailingView: nil)

        let stack = NSStackView(views: [
            shortcutRow,
            folderRow,
            themeRow,
            launchRow,
            exportModeRow,
            recordingFormatRow,
            fileNamePrefixRow,
            timestampTemplateRow,
            revealSavedFileButton,
            noteLabel,
            resetButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            shortcutRecorderButton.widthAnchor.constraint(equalToConstant: 220),
            themePopupButton.widthAnchor.constraint(equalToConstant: 160),
            exportBehaviorPopupButton.widthAnchor.constraint(equalToConstant: 180),
            recordingFormatPopupButton.widthAnchor.constraint(equalToConstant: 120),
            fileNamePrefixField.widthAnchor.constraint(equalToConstant: 280),
            timestampTemplateField.widthAnchor.constraint(equalToConstant: 280),
            saveLocationControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])

        syncFromPreferences()
        view = root
    }

    @objc
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.saveDirectoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.saveDirectoryURL = url
        saveLocationControl.url = url
    }

    @objc
    private func revealFolder() {
        NSWorkspace.shared.open(preferences.saveDirectoryURL)
    }

    @objc
    private func themeChanged(_ sender: NSPopUpButton) {
        guard let theme = sender.selectedItem?.representedObject as? AppPreferences.Theme else { return }
        preferences.theme = theme
    }

    @objc
    private func exportBehaviorChanged(_ sender: NSPopUpButton) {
        guard let behavior = sender.selectedItem?.representedObject as? AppPreferences.ExportBehavior else { return }
        preferences.exportBehavior = behavior
    }

    @objc
    private func recordingFormatChanged(_ sender: NSPopUpButton) {
        guard let format = sender.selectedItem?.representedObject as? AppPreferences.RecordingFileFormat else { return }
        preferences.recordingFileFormat = format
    }

    @objc
    private func fileNamePrefixChanged(_ sender: NSTextField) {
        preferences.fileNamePrefix = sender.stringValue
        sender.stringValue = preferences.fileNamePrefix
    }

    @objc
    private func timestampTemplateChanged(_ sender: NSTextField) {
        preferences.timestampTemplate = sender.stringValue
        sender.stringValue = preferences.timestampTemplate
    }

    @objc
    private func launchAtLoginChanged(_ sender: NSButton) {
        preferences.launchAtLogin = sender.state == .on
    }

    @objc
    private func revealSavedFileChanged(_ sender: NSButton) {
        preferences.revealSavedFile = sender.state == .on
    }

    @objc
    private func resetToDefaults() {
        preferences.resetToDefaults()
        syncFromPreferences()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fileNamePrefixField {
            fileNamePrefixChanged(field)
        } else if field === timestampTemplateField {
            timestampTemplateChanged(field)
        }
    }

    private func syncFromPreferences() {
        shortcutRecorderButton.descriptor = preferences.captureHotkey
        saveLocationControl.url = preferences.saveDirectoryURL
        fileNamePrefixField.stringValue = preferences.fileNamePrefix
        timestampTemplateField.stringValue = preferences.timestampTemplate
        launchAtLoginButton.state = preferences.launchAtLogin ? .on : .off
        revealSavedFileButton.state = preferences.revealSavedFile ? .on : .off

        if let themeIndex = AppPreferences.Theme.allCases.firstIndex(of: preferences.theme) {
            themePopupButton.selectItem(at: themeIndex)
        }

        if let behaviorIndex = AppPreferences.ExportBehavior.allCases.firstIndex(of: preferences.exportBehavior) {
            exportBehaviorPopupButton.selectItem(at: behaviorIndex)
        }

        if let formatIndex = AppPreferences.RecordingFileFormat.allCases.firstIndex(of: preferences.recordingFileFormat) {
            recordingFormatPopupButton.selectItem(at: formatIndex)
        }
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func makeRow(label: NSView, mainView: NSView, trailingView: NSView?) -> NSView {
        makeRow(label: label, mainView: mainView, trailingViews: trailingView.map { [$0] } ?? [])
    }

    private func makeRow(label: NSView, mainView: NSView, trailingViews: [NSView]) -> NSView {
        var views = [label, mainView]
        views.append(contentsOf: trailingViews)
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
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

        let descriptor = HotkeyManager.HotkeyDescriptor(id: HotkeyManager.defaultCaptureHotkey.id, keyCode: UInt32(event.keyCode), modifiers: modifiers)
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

private enum HotkeyFormatter {
    static func string(for descriptor: HotkeyManager.HotkeyDescriptor) -> String {
        modifierSymbols(for: descriptor.modifiers) + keyName(for: descriptor.keyCode)
    }

    private static func modifierSymbols(for modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let specialKeyName = specialKeyName(for: keyCode) {
            return specialKeyName
        }
        if let translatedKeyName = translatedKeyName(for: keyCode) {
            return translatedKeyName
        }
        return "Key \(keyCode)"
    }

    private static func translatedKeyName(for keyCode: UInt32) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        return data.withUnsafeBytes { rawBuffer in
            guard let keyboardLayout = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var unicodeScalars = [UniChar](repeating: 0, count: 4)

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                unicodeScalars.count,
                &actualLength,
                &unicodeScalars
            )

            guard status == noErr, actualLength > 0 else {
                return nil
            }

            let string = String(utf16CodeUnits: unicodeScalars, count: actualLength)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !string.isEmpty else {
                return nil
            }
            return string.uppercased()
        }
    }

    private static func specialKeyName(for keyCode: UInt32) -> String? {
        switch keyCode {
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_Escape): return "Esc"
        case UInt32(kVK_ForwardDelete): return "Forward Delete"
        case UInt32(kVK_LeftArrow): return "Left Arrow"
        case UInt32(kVK_RightArrow): return "Right Arrow"
        case UInt32(kVK_UpArrow): return "Up Arrow"
        case UInt32(kVK_DownArrow): return "Down Arrow"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        default: return nil
        }
    }
}
