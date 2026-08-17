import AppKit

enum MenuBarLabel {
    static let height: CGFloat = 16
    static let dotDiameter: CGFloat = 6
    static let dotGap: CGFloat = 5
    static let trailingInset: CGFloat = 1

    static let widestText = "888 ms"

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    static func text(for state: PingState) -> String {
        switch state {
        case .waiting: return "···"
        case .dns: return "DNS"
        case .offline: return "---"
        case .ok(let rtt), .slow(let rtt): return milliseconds(rtt)
        }
    }

    static func milliseconds(_ rtt: TimeInterval) -> String {
        let value = rtt * 1000
        if value >= 999.5 { return String(format: "%.1f s", value / 1000) }
        if value < 1 { return "<1 ms" }
        return "\(Int(value.rounded())) ms"
    }

    static func colour(for state: PingState) -> NSColor {
        switch state {
        case .waiting: return .tertiaryLabelColor
        case .ok: return .systemGreen
        case .slow: return .systemOrange
        case .dns: return .systemYellow
        case .offline: return .systemRed
        }
    }

    static func width(of text: String, showDot: Bool) -> CGFloat {
        let reserved = max(measure(widestText), measure(text))
        let lead = showDot ? dotDiameter + dotGap : 0
        return (lead + reserved + trailingInset).rounded(.up)
    }

    static func image(for state: PingState, showDot: Bool = true, appearance: NSAppearance? = nil) -> NSImage {
        let label = text(for: state)
        let size = NSSize(width: width(of: label, showDot: showDot), height: height)
        let dotColour = colour(for: state)
        let image = NSImage(size: size)

        draw(under: appearance) {
            image.lockFocus()
            defer { image.unlockFocus() }

            let drawn = NSAttributedString(
                string: label, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            let textSize = drawn.size()
            drawn.draw(
                at: NSPoint(
                    x: size.width - trailingInset - textSize.width,
                    y: ((size.height - textSize.height) / 2).rounded()))

            guard showDot else { return }
            let dot = NSRect(
                x: 0,
                y: ((size.height - dotDiameter) / 2).rounded(),
                width: dotDiameter,
                height: dotDiameter)
            dotColour.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        image.accessibilityDescription = accessibilityDescription(for: state)
        return image
    }

    private static func draw(under appearance: NSAppearance?, _ body: () -> Void) {
        guard let appearance = appearance ?? NSApp?.effectiveAppearance else { return body() }
        appearance.performAsCurrentDrawingAppearance(body)
    }

    static func accessibilityDescription(for state: PingState) -> String {
        switch state {
        case .waiting: return "waiting for the first reply"
        case .ok(let rtt): return "ping \(milliseconds(rtt))"
        case .slow(let rtt): return "ping \(milliseconds(rtt)), slow"
        case .dns: return "DNS unreachable"
        case .offline: return "no connection"
        }
    }

    private static func measure(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width.rounded(.up)
    }
}
