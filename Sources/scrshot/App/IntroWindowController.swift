import AppKit
import SwiftUI

@MainActor
final class IntroWindowController: NSWindowController {
    private let onClose: () -> Void

    init(hotkeyTitle: String, appVersionTitle: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        weak var introWindow: NSWindow?
        let contentView = IntroSceneView(
            hotkeyTitle: hotkeyTitle,
            appVersionTitle: appVersionTitle,
            dismissAction: {
                introWindow?.close()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to scrshot"
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        introWindow = window
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.recenterOnActiveScreenAfterLayout()
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension IntroWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct IntroSceneView: View {
    let hotkeyTitle: String
    let appVersionTitle: String
    let dismissAction: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            MenuBarOverflowDiagram()
                .frame(height: 80)
                .padding(.horizontal, 2)
            
            Text("scrshot lives in the menu bar. If the right side fills up, macOS can hide app icons behind the notch or menu items, so keep enough space to reach the capture and recording controls.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Text("Default capture shortcut")
                    .font(.headline)
                Text(hotkeyTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button("Got it") {
                dismissAction()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 480)
    }

    private var appIconImage: NSImage {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            return iconImage
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

private struct MenuBarOverflowDiagram: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                Text("Finder")
                    .font(.caption.weight(.semibold))
                    .frame(width: 54, height: 26)
                menuText("File")
                menuText("Edit")
                menuText("View")
                Spacer(minLength: 8)
                icon(systemName: "camera.viewfinder", highlighted: true)
                icon(systemName: "wifi")
                icon(systemName: "battery.100")
                icon(systemName: "record.circle")
                Text("Tue 10:11")
                    .font(.caption)
                    .frame(width: 58, height: 28)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                OverflowMask()
                    .frame(width: 80, height: 50)
                    .offset(x: -152, y: -7)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                Text("The icon area can run out of room")
            }.offset(x: 100)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private func menuText(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .frame(width: 38, height: 26)
    }

    private func icon(systemName: String, highlighted: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: highlighted ? .semibold : .regular))
            .foregroundStyle(highlighted ? Color.accentColor : .primary)
            .frame(width: 28, height: 28)
    }
}

private struct OverflowMask: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.background.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .overlay {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
            }
    }
}

#if DEBUG
struct IntroSceneView_Previews: PreviewProvider {
    static var previews: some View {
        IntroSceneView(
            hotkeyTitle: "⌘ + Shift + 1",
            appVersionTitle: "Version 1.3",
            dismissAction: {}
        )
    }
}
#endif
