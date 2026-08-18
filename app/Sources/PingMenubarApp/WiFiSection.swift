import SwiftUI

struct WiFiSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DisclosureGroup(isExpanded: $model.wifiExpanded) {
            content.padding(.top, 6)
        } label: {
            summary
        }
        .disclosureGroupStyle(SectionDisclosureStyle { SignalGraph(samples: model.signal).padding(.top, 6) })
    }

    private var wifi: WiFiSnapshot? { model.wifi }

    private var summary: some View {
        HStack(spacing: 6) {
            Text("Wi-Fi").font(.callout)
            Spacer()
            if let wifi, wifi.powered, let rssi = wifi.rssi {
                SignalBars(quality: wifi.quality ?? 0)
                Text("\(rssi) dBm")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(wifi?.powered == false ? "off" : "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var content: some View {
        WiFiDetails(wifi: wifi, log: model.wifiLog)
    }
}

struct WiFiDetails: View {
    let wifi: WiFiSnapshot?
    var log: [LogEntry] = []

    var body: some View {
        if let wifi, wifi.powered {
            VStack(alignment: .leading, spacing: 3) {
                if let rssi = wifi.rssi {
                    row("Signal", [String(rssi) + " dBm", wifi.qualityLabel])
                }
                if let noise = wifi.noise {
                    row("Noise", [String(noise) + " dBm", wifi.snr.map { "SNR \($0) dB" }])
                }
                if let rate = wifi.transmitRate { row("Rate", [WiFiNames.rate(rate)]) }
                if let throughput = wifi.throughput {
                    row(
                        "Traffic",
                        [
                            "↓ " + WiFiNames.throughput(throughput.down),
                            "↑ " + WiFiNames.throughput(throughput.up),
                        ])
                } else {
                    row("Traffic", ["measuring…"])
                }
                if let channel = wifi.channel {
                    row("Channel", [String(channel), wifi.band, wifi.width])
                }
                row("Link", [wifi.standard, wifi.security])
                row("Device", [wifi.interfaceName, wifi.ipv4])
                if let gateway = wifi.gateway { row("Gateway", [gateway]) }
                if let upstream = wifi.upstream { row("Upstream", [upstream]) }
                WiFiLogView(entries: log)
            }
        } else {
            Text(wifi?.powered == false ? "Wi-Fi is turned off." : "No Wi-Fi interface.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func row(_ title: String, _ parts: [String?]) -> some View {
        StatRow(title: title, parts: parts)
    }
}

struct WiFiLogView: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.vertical, 4)
            box {
                if entries.isEmpty {
                    Text("no wifi changes yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SelectableLog(entries: entries)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func box(@ViewBuilder _ inner: () -> some View) -> some View {
        inner()
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct StatRow: View {
    let title: String
    let parts: [String?]

    var body: some View {
        let value = parts.compactMap { $0 }.joined(separator: " · ")
        if !value.isEmpty {
            HStack(spacing: 6) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
        }
    }
}

struct SignalBars: View {
    let quality: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(lit(index) ? Color.primary.opacity(0.75) : Color.primary.opacity(0.15))
                    .frame(width: 2, height: 3 + CGFloat(index) * 2.5)
            }
        }
        .frame(height: 10, alignment: .bottom)
    }

    private func lit(_ index: Int) -> Bool {
        Double(index) < (quality * 4).rounded(.up)
    }
}

struct SectionDisclosureStyle<Accessory: View>: DisclosureGroupStyle {
    @ViewBuilder var accessory: () -> Accessory

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            accessory()

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

extension DisclosureGroupStyle where Self == SectionDisclosureStyle<EmptyView> {
    static var section: Self { SectionDisclosureStyle { EmptyView() } }
}
