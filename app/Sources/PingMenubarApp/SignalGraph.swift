import SwiftUI

enum SignalScale {
    static let floor: Double = -100
    static let ceiling: Double = -50
    static let good: Double = -67

    static func quality(_ dBm: Double) -> Double {
        min(max((dBm - floor) / (ceiling - floor), 0), 1)
    }

    static func tint(_ quality: Double) -> Color {
        switch quality {
        case 0.66...: return .green
        case 0.4..<0.66: return .yellow
        default: return .orange
        }
    }
}

struct SignalGraph: View {
    let samples: Samples

    static let height: CGFloat = 40
    static let window: TimeInterval = 300
    static let gapWidth: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                if samples.total < 2 {
                    Text("collecting…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Canvas { context, size in draw(in: &context, size: size) }
                        .padding(.vertical, 3)
                }
            }
            .frame(height: SignalGraph.height)
            HStack {
                Text("\(Int(SignalScale.ceiling)) dBm full scale")
                Spacer()
                Text("last \(Int(SignalGraph.window / 60))m")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    var tint: Color {
        SignalScale.tint(samples.lastReceived.map(SignalScale.quality) ?? 0)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let start = samples.start, let end = samples.end, end > start else { return }

        let span = end - start
        func position(_ at: TimeInterval) -> CGFloat {
            size.width * CGFloat((at - start) / span)
        }
        func height(_ dBm: Double) -> CGFloat {
            size.height * CGFloat(SignalScale.quality(dBm))
        }

        for sample in samples.values where sample.lost {
            let x = position(sample.at)
            context.fill(
                Path(
                    CGRect(
                        x: x - SignalGraph.gapWidth / 2, y: 0,
                        width: SignalGraph.gapWidth, height: size.height)),
                with: .color(.secondary.opacity(0.2)))
        }

        let y = size.height - size.height * CGFloat(SignalScale.quality(SignalScale.good))
        var threshold = Path()
        threshold.move(to: CGPoint(x: 0, y: y))
        threshold.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
            threshold,
            with: .color(.secondary.opacity(0.4)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        let tint = tint
        for run in LatencyGraph.runs(of: samples.values) {
            let points = run.map { sample in
                CGPoint(x: position(sample.at), y: size.height - height(sample.value ?? 0))
            }
            guard let first = points.first, let last = points.last else { continue }

            guard points.count > 1 else {
                let dot = CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)
                context.fill(Path(ellipseIn: dot), with: .color(tint))
                continue
            }

            var fill = Path()
            fill.move(to: CGPoint(x: first.x, y: size.height))
            for point in points { fill.addLine(to: point) }
            fill.addLine(to: CGPoint(x: last.x, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.3), tint.opacity(0.03)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))

            var line = Path()
            line.addLines(points)
            context.stroke(
                line,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
