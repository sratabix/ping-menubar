import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            LatencyGraph(samples: model.samples, warn: model.warnThreshold)
            stats
            if let detail = model.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            WiredSection()
            WiFiSection()
            Divider()
            actions
        }
        .padding(12)
        .frame(width: ContentView.width)
        .onAppear { model.showNetworkDetail() }
        .onDisappear { model.hideNetworkDetail() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.host).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: MenuBarLabel.colour(for: model.state)))
                    .frame(width: 8, height: 8)
                Text(MenuBarLabel.text(for: model.state))
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let address = model.address, address != model.host { parts.append(address) }
        parts.append(model.mode == .tcp ? "tcp :\(model.tcpPort)" : "icmp")
        if !model.reachable { parts.append("no network") }
        return parts.joined(separator: " · ")
    }

    private var stats: some View {
        VStack(spacing: 4) {
            row("avg", value: format(model.samples.average))
            row("min", value: format(model.samples.minimum))
            row("max", value: format(model.samples.maximum))
            row("loss", value: lossText)
        }
    }

    private var lossText: String {
        let samples = model.samples
        guard samples.total > 0 else { return "—" }
        return "\(Int((samples.loss * 100).rounded()))% (\(samples.lost)/\(samples.total))"
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Settings…") { model.openSettings() }
            Button("Quit") { model.quit() }
        }
        .controlSize(.small)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func format(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return MenuBarLabel.milliseconds(value)
    }
}
