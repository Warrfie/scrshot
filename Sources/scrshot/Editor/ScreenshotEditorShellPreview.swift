import AppKit
import SwiftUI

#if DEBUG
@MainActor
private enum ScreenshotEditorShellPreviewFactory {
    static func makeViewModel() -> ScreenshotEditorShellViewModel {
        let viewModel = ScreenshotEditorShellViewModel()
        viewModel.apply(
            ScreenshotEditorShellState(
                selectedTool: .rectangle,
                inspectorKind: .rectangle,
                annotationColor: .systemRed,
                rectangleColor: .black,
                arrowStrokeWidth: 8,
                rectangleMode: .outline,
                rectangleStrokeEnabled: true,
                detailScale: 2.4,
                lineStyle: .dashed,
                textSize: 28,
                textAlignment: .center
            )
        )
        return viewModel
    }

    static func sampleImage() -> CGImage {
        let size = CGSize(width: 1440, height: 900)
        let renderer = NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.86, green: 0.9, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 80, y: 120, width: 420, height: 220), xRadius: 24, yRadius: 24).fill()
            NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.29, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 560, y: 250, width: 620, height: 320), xRadius: 30, yRadius: 30).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.29, alpha: 1),
                .paragraphStyle: paragraph
            ]
            NSString(string: "scrshot preview").draw(in: NSRect(x: 86, y: 384, width: 500, height: 52), withAttributes: attrs)
            return true
        }
        return renderer.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

private struct InteractiveScreenshotEditorShellPreview: View {
    @StateObject private var viewModel = ScreenshotEditorShellPreviewFactory.makeViewModel()

    var body: some View {
        ScreenshotEditorShellView(viewModel: viewModel, ignoresTopSafeArea: false) {
            ZStack(alignment: .topLeading) {
                Image(decorative: ScreenshotEditorShellPreviewFactory.sampleImage(), scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.selectedTool.rawValue)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(previewInspectorSummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                )
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(width: 1120, height: 760)
    }

    private var previewInspectorSummary: String {
        switch viewModel.selectedTool {
        case .hand:
            return "Move around the canvas"
        case .crop:
            return "Fit action is available"
        case .arrow:
            return "Stroke \(Int(viewModel.arrowStrokeWidth)) pt, color preview enabled"
        case .line:
            return "Line style: \(viewModel.lineStyle.title)"
        case .rectangle:
            return "Mode: \(viewModel.rectangleMode.title)"
        case .detail:
            return "Zoom \(String(format: "%.1fx", viewModel.detailScale))"
        case .text:
            return "Text \(Int(viewModel.textSize)) pt"
        }
    }
}

struct ScreenshotEditorShellView_Previews: PreviewProvider {
    static var previews: some View {
        InteractiveScreenshotEditorShellPreview()
    }
}
#endif
