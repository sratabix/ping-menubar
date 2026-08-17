import AppKit
import SwiftUI

final class LogTextView: NSTextView {
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage else {
            return
        }

        let text = storage.string as NSString
        var location = 0
        var row = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            if row.isMultiple(of: 2) {
                let glyphs = layout.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
                var stripe = layout.boundingRect(forGlyphRange: glyphs, in: container)
                stripe.origin.x = 0
                stripe.origin.y += textContainerInset.height
                stripe.size.width = bounds.width
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                stripe.fill()
            }
            location = NSMaxRange(paragraph)
            row += 1
        }
    }
}

struct SelectableLog: NSViewRepresentable {
    let entries: [LogEntry]

    static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
    static let gap = "  "
    static let inset = NSSize(width: 6, height: 4)
    static let maxHeight: CGFloat = 150

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = SelectableLog.make()
        return scroll
    }

    static func make() -> LogTextView {
        let view = LogTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = SelectableLog.inset
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.selectedTextAttributes = [.backgroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.3)]
        return view
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? LogTextView else { return }
        let updated = attributed
        guard view.attributedString() != updated else { return }
        let selection = view.selectedRanges
        view.textStorage?.setAttributedString(updated)
        let length = updated.length
        view.selectedRanges = selection.filter { NSMaxRange($0.rangeValue) <= length }
        view.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        return CGSize(width: width, height: SelectableLog.height(of: attributed, width: width))
    }

    static func height(of attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attributed.length > 0 else { return inset.height * 2 }
        let storage = NSTextStorage(attributedString: attributed)
        let container = NSTextContainer(
            size: NSSize(width: width - inset.width * 2, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let content = layout.usedRect(for: container).height + inset.height * 2
        return min(content, maxHeight).rounded(.up)
    }

    var attributed: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 2
        paragraph.paragraphSpacingBefore = 2
        paragraph.headIndent = indent

        let log = NSMutableAttributedString()
        for entry in entries {
            log.append(
                NSAttributedString(
                    string: WiFiLog.time.string(from: entry.at) + SelectableLog.gap,
                    attributes: [.font: SelectableLog.font, .foregroundColor: NSColor.tertiaryLabelColor]))
            log.append(
                NSAttributedString(
                    string: entry.text,
                    attributes: [.font: SelectableLog.font, .foregroundColor: NSColor.secondaryLabelColor]))
            if entry.id != entries.last?.id { log.append(NSAttributedString(string: "\n")) }
        }
        log.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: log.length))
        return log
    }

    var indent: CGFloat {
        let sample = WiFiLog.time.string(from: Date()) + SelectableLog.gap
        return (sample as NSString).size(withAttributes: [.font: SelectableLog.font]).width
    }
}
