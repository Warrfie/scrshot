import AppKit

final class InlineTextEditorView: NSView {
    let textView: NSTextView
    private let padding = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    override var isFlipped: Bool { true }

    init(frame frameRect: CGRect, color: NSColor, fontSize: CGFloat, alignment: NSTextAlignment, showsBackground: Bool, backgroundColor: NSColor) {
        let textContainer = NSTextContainer(size: NSSize(width: max(frameRect.width - 24, 80), height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let textView = NSTextView(frame: frameRect.insetBy(dx: 12, dy: 8), textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = false
        textView.allowsUndo = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        self.textView = textView
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        addSubview(textView)
        updateStyle(color: color, fontSize: fontSize, alignment: alignment, showsBackground: showsBackground, backgroundColor: backgroundColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateStyle(color: NSColor, fontSize: CGFloat, alignment: NSTextAlignment, showsBackground: Bool, backgroundColor: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        if textView.textStorage?.length ?? 0 > 0 {
            textView.textStorage?.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        }
        layer?.backgroundColor = showsBackground ? backgroundColor.cgColor : NSColor.clear.cgColor
    }

    func updateFrame(origin: CGPoint, width: CGFloat, height: CGFloat) {
        frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        textView.frame = bounds.insetBy(dx: padding.left, dy: padding.top)
        textView.textContainer?.containerSize = NSSize(width: max(bounds.width - padding.left - padding.right, 80), height: .greatestFiniteMagnitude)
    }

    func measuredHeight() -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return max(56, textView.font?.pointSize ?? 24)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return ceil(max(usedHeight + padding.top + padding.bottom, (textView.font?.pointSize ?? 24) + padding.top + padding.bottom + 8))
    }
}
