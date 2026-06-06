import AppKit
import SwiftUI

private let textAlignmentOptions: [(alignment: NSTextAlignment, symbol: String, help: String)] = [
    (.left, "text.alignleft", "Align Left"),
    (.center, "text.aligncenter", "Align Center"),
    (.right, "text.alignright", "Align Right")
]

private enum EditorToolbarMetrics {
    static let standardControlSize: CGFloat = 40
    static let standardIconSize: CGFloat = 17
    static let doneButtonWidth: CGFloat = standardControlSize * 2 / 1.5
    static let doneButtonHeight: CGFloat = standardControlSize / 1.5
}

struct ScreenshotEditorToolbarView: View {
    @ObservedObject var viewModel: ScreenshotEditorShellViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            ScreenshotEditorWindowTrafficLightsView(viewModel: viewModel)
            ScreenshotEditorTitlebarLeadingControlsView(viewModel: viewModel)
            Spacer(minLength: 12)
            ScreenshotEditorTitlebarTrailingControlsView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScreenshotEditorWindowTrafficLightsView: View {
    @ObservedObject var viewModel: ScreenshotEditorShellViewModel
    @State private var isHoveringGroup = false

    var body: some View {
        HStack(spacing: 8) {
            trafficLight(color: Color(red: 1.0, green: 0.37, blue: 0.33), symbol: "xmark") {
                viewModel.closeWindow()
            }
            trafficLight(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus") {
                viewModel.minimizeWindow()
            }
            trafficLight(color: Color(red: 0.16, green: 0.80, blue: 0.25), symbol: "plus") {
                viewModel.zoomWindow()
            }
        }
        .contentShape(Rectangle())
        .onHover { isHoveringGroup = $0 }
    }

    private func trafficLight(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        ScreenshotEditorTrafficLightButton(
            color: color,
            symbol: symbol,
            showsSymbol: isHoveringGroup,
            action: action
        )
    }
}

private struct ScreenshotEditorTrafficLightButton: View {
    let color: Color
    let symbol: String
    let showsSymbol: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.96), color.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.6)
                )
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .opacity(showsSymbol ? 1 : 0)
                )
                .frame(width: 12, height: 12)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

struct ScreenshotEditorTitlebarLeadingControlsView: View {
    @ObservedObject var viewModel: ScreenshotEditorShellViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            toolStrip
            currentInspectorPanel
        }
    }

    private var toolStrip: some View {
        HStack(spacing: 2) {
            ForEach(ScreenshotEditorTool.allCases, id: \.self) { tool in
                Button {
                    viewModel.selectTool(tool)
                } label: {
                    ZStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.001))
                        Image(systemName: tool.symbolName)
                            .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .medium))
                            .foregroundStyle(tool == viewModel.selectedTool ? Color.accentColor : Color.primary.opacity(0.78))
                    }
                    .editorToolbarControlFrame()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.rawValue)
                .editorToolbarButtonBackground(isSelected: tool == viewModel.selectedTool)
            }
        }
    }

    @ViewBuilder
    private var currentInspectorPanel: some View {
        switch viewModel.inspectorKind {
        case .none:
            EmptyView()
        case .crop:
            cropInspectorPanel
        case .arrow:
            arrowInspectorPanel
        case .line:
            lineInspectorPanel
        case .rectangle:
            rectangleInspectorPanel
        case .detail:
            detailInspectorPanel
        case .text:
            textInspectorPanel
        }
    }

    private var cropInspectorPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: { viewModel.fit() }) {
                ZStack {
                    Rectangle()
                        .fill(Color.primary.opacity(0.001))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .semibold))
                }
                .editorToolbarControlFrame()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .editorToolbarButtonBackground(isSelected: false)
            .help("Fit")
        }
    }

    private var arrowInspectorPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            annotationColorSection
            strokeWidthSection()
        }
    }

    private var lineInspectorPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            annotationColorSection
            strokeWidthSection()
            lineStyleSection
        }
    }

    private var rectangleInspectorPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            rectangleModeSection
            if viewModel.rectangleMode != .blur {
                rectangleColorSection
                strokeWidthSection(minValue: 0)
            }
        }
    }

    private var detailInspectorPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            annotationColorSection
            strokeWidthSection(minValue: 0)
            detailShapeSection
        }
    }

    private var textInspectorPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            annotationColorSection
            textSizeSection
            textAlignmentSection
        }
    }

    private var annotationColorSection: some View {
        inspectorSection {
            inspectorColorControl(
                color: Binding(
                    get: { viewModel.annotationColor },
                    set: { viewModel.setAnnotationColor($0) }
                )
            ).editorToolbarControlFrame()
        }
    }

    private func strokeWidthSection(minValue: CGFloat = 2) -> some View {
        inspectorSection(isSlider: true) {
            Slider(
                value: Binding(
                    get: { viewModel.arrowStrokeWidth },
                    set: { viewModel.setArrowStrokeWidth($0) }
                ),
                in: minValue...24
            )
            .frame(width: 120)
        }
    }

    private var detailShapeSection: some View {
        inspectorSection(isWideControl: true) {
            HStack(spacing: 0) {
                ForEach(ScreenshotDetailShape.allCases, id: \.self) { shape in
                    Button {
                        viewModel.setDetailShape(shape)
                    } label: {
                        ZStack {
                            Rectangle()
                                .fill(Color.primary.opacity(0.001))
                            Image(systemName: shape.symbolName)
                                .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.detailShape == shape
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.78)
                                )
                        }
                        .editorToolbarControlFrame()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .editorToolbarButtonBackground(isSelected: viewModel.detailShape == shape)
                    .help(shape.title)
                }
            }
            .frame(height: EditorToolbarMetrics.standardControlSize)
        }
    }

    private var lineStyleSection: some View {
        inspectorSection(isWideControl: true) {
            HStack(spacing: 0) {
                ForEach(ScreenshotLineStyle.allCases, id: \.self) { style in
                    Button {
                        viewModel.setLineStyle(style)
                    } label: {
                        ZStack {
                            Rectangle()
                                .fill(Color.primary.opacity(0.001))
                            Image(systemName: lineStyleSymbol(for: style))
                                .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.lineStyle == style
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.78)
                                )
                        }
                        .editorToolbarControlFrame()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .editorToolbarButtonBackground(isSelected: viewModel.lineStyle == style)
                    .help(style.title)
                }
            }
            .frame(height: EditorToolbarMetrics.standardControlSize)
        }
    }

    private var rectangleModeSection: some View {
        inspectorSection(isWideControl: true) {
            HStack(spacing: 0) {
                ForEach(ScreenshotRectangleToolMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.setRectangleMode(mode)
                    } label: {
                        ZStack {
                            Rectangle()
                                .fill(Color.primary.opacity(0.001))
                            Image(systemName: rectangleModeSymbol(for: mode))
                                .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.rectangleMode == mode
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.78)
                                )
                        }
                        .editorToolbarControlFrame()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .editorToolbarButtonBackground(isSelected: viewModel.rectangleMode == mode)
                    .help(mode.title)
                }
            }
            .frame(height: EditorToolbarMetrics.standardControlSize)
        }
    }

    private var rectangleColorSection: some View {
        inspectorSection {
            inspectorColorControl(
                color: Binding(
                    get: { viewModel.rectangleColor },
                    set: { viewModel.setRectangleColor($0) }
                )
            )
        }
    }

    private var textSizeSection: some View {
        inspectorSection(isSlider: true) {
            Slider(
                value: Binding(
                    get: { viewModel.textSize },
                    set: { viewModel.setTextSize($0) }
                ),
                in: 12...96
            )
            .frame(width: 120)
        }
    }

    private var textAlignmentSection: some View {
        inspectorSection(isWideControl: true) {
            HStack(spacing: 0) {
                ForEach(textAlignmentOptions, id: \.alignment) { option in
                    Button {
                        viewModel.setTextAlignment(option.alignment)
                    } label: {
                        ZStack {
                            Rectangle()
                                .fill(Color.primary.opacity(0.001))
                            Image(systemName: option.symbol)
                                .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.textAlignment == option.alignment
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.78)
                                )
                        }
                        .editorToolbarControlFrame()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .editorToolbarButtonBackground(isSelected: viewModel.textAlignment == option.alignment)
                    .help(option.help)
                }
            }
            .frame(height: EditorToolbarMetrics.standardControlSize)
        }
    }

    @ViewBuilder
    private func inspectorColorControl(color: Binding<NSColor>) -> some View {
        CompactInspectorColorWell(color: color)
            .editorToolbarControlFrame()
    }

    private func lineStyleSymbol(for style: ScreenshotLineStyle) -> String {
        switch style {
        case .solid:
            return "line.diagonal"
        case .dashed:
            return "scribble"
        case .dotted:
            return "ellipsis"
        case .dashDotted:
            return "alternatingcurrent"
        }
    }

    private func rectangleModeSymbol(for mode: ScreenshotRectangleToolMode) -> String {
        switch mode {
        case .highlight:
            return "square.fill"
        case .blur:
            return "drop"
        case .outline:
            return "square"
        }
    }

    private func inspectorSection<Content: View>(
        isSlider: Bool = false,
        isWideControl: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(minHeight: EditorToolbarMetrics.standardControlSize)
        .padding(.horizontal, isSlider ? 8 : 0)
        .frame(
            width: isWideControl ? nil : (isSlider ? nil : EditorToolbarMetrics.standardControlSize),
            height: EditorToolbarMetrics.standardControlSize
        )
    }
}

struct ScreenshotEditorTitlebarTrailingControlsView: View {
    @ObservedObject var viewModel: ScreenshotEditorShellViewModel

    var body: some View {
        Button(action: { viewModel.done() }) {
            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                Image(systemName: "checkmark")
                    .font(.system(size: EditorToolbarMetrics.standardIconSize, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(
                width: EditorToolbarMetrics.doneButtonWidth,
                height: EditorToolbarMetrics.doneButtonHeight
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.blue)
        )
        .help("Done")
    }
}

private struct CompactInspectorColorWell: View {
    @Binding var color: NSColor

    var body: some View {
        Button {
            InspectorColorPanelController.shared.open(color: color) { newColor in
                color = newColor
            }
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.001))

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: color))
                    .frame(width: 18, height: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.black.opacity(0.16), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
            }
            .editorToolbarControlFrame()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Color")
    }
}

@MainActor
private final class InspectorColorPanelController: NSObject {
    static let shared = InspectorColorPanelController()

    private var onChange: ((NSColor) -> Void)?

    func open(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.color = color
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc
    private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

private extension View {
    func editorToolbarControlFrame() -> some View {
        frame(
            width: EditorToolbarMetrics.standardControlSize,
            height: EditorToolbarMetrics.standardControlSize
        )
    }

    func editorToolbarButtonBackground(isSelected: Bool) -> some View {
        modifier(EditorToolbarButtonBackground(isSelected: isSelected))
    }

}

private struct EditorToolbarButtonBackground: ViewModifier {
    let isSelected: Bool

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundStyle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.34) : Color.clear, lineWidth: 0.8)
            )
            .onHover { isHovering = $0 }
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else if isHovering {
            AnyShapeStyle(Color.primary.opacity(0.07))
        } else {
            AnyShapeStyle(Color.clear)
        }
    }
}
