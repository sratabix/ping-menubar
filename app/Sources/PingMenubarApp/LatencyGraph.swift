import SwiftUI

struct LatencyGraph: View {
    let samples: Samples
    let warn: TimeInterval

    static let height: CGFloat = 52
    static let lossWidth: CGFloat = 2

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
            .frame(height: LatencyGraph.height)
            HStack {
                Text(ceiling.map { "\(MenuBarLabel.milliseconds($0)) full scale" } ?? "")
                Spacer()
                Text("last \(Int(samples.window))s")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    var ceiling: TimeInterval? {
        guard let maximum = samples.maximum else { return nil }
        return max(maximum, warn * 1.25)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard
            let start = samples.start,
            let end = samples.end,
            let ceiling, ceiling > 0,
            end > start
        else { return }

        let span = end - start
        func position(_ at: TimeInterval) -> CGFloat {
            size.width * CGFloat((at - start) / span)
        }
        func height(_ rtt: TimeInterval) -> CGFloat {
            size.height * CGFloat(min(rtt / ceiling, 1))
        }

        for sample in samples.values where sample.lost {
            let x = position(sample.at)
            context.fill(
                Path(
                    CGRect(
                        x: x - LatencyGraph.lossWidth / 2, y: 0,
                        width: LatencyGraph.lossWidth, height: size.height)),
                with: .color(.red.opacity(0.45)))
        }

        if warn < ceiling {
            let y = size.height - size.height * CGFloat(warn / ceiling)
            var threshold = Path()
            threshold.move(to: CGPoint(x: 0, y: y))
            threshold.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                threshold,
                with: .color(.orange.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }

        for run in LatencyGraph.runs(of: samples.values) {
            let points = run.map { sample in
                CGPoint(x: position(sample.at), y: size.height - height(sample.rtt ?? 0))
            }
            guard let first = points.first, let last = points.last else { continue }

            guard points.count > 1 else {
                let dot = CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)
                context.fill(Path(ellipseIn: dot), with: .color(.accentColor))
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
                    Gradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.03)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))

            var line = Path()
            line.addLines(points)
            context.stroke(
                line,
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    static func runs(of samples: [Sample]) -> [[Sample]] {
        samples.reduce(into: [[Sample]]()) { runs, sample in
            guard !sample.lost else { return runs.append([]) }
            if runs.isEmpty { runs.append([]) }
            runs[runs.count - 1].append(sample)
        }
        .filter { !$0.isEmpty }
    }
}
