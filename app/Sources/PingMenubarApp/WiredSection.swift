import SwiftUI

struct WiredSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if !model.wired.isEmpty {
            DisclosureGroup(isExpanded: $model.wiredExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.wired, id: \.device) { wired in
                        WiredDetails(wired: wired)
                    }
                }
                .padding(.top, 6)
            } label: {
                summary
            }
            .disclosureGroupStyle(.section)
        }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Text("Ethernet").font(.callout)
            Spacer()
            Text(state)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(
                    model.wired.contains { $0.linkUp } ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        }
    }

    private var state: String {
        if let linked = model.wired.first(where: { $0.linkUp }) {
            return linked.speed ?? "linked"
        }
        return model.wired.count > 1 ? "\(model.wired.count) adapters" : "no cable"
    }
}

struct WiredDetails: View {
    let wired: WiredSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            StatRow(title: "Adapter", parts: [wired.adapter])
            if wired.linkUp {
                StatRow(title: "Link", parts: [wired.speed, wired.duplex])
                if let throughput = wired.throughput {
                    StatRow(
                        title: "Traffic",
                        parts: [
                            "↓ " + WiFiNames.throughput(throughput.down),
                            "↑ " + WiFiNames.throughput(throughput.up),
                        ])
                } else {
                    StatRow(title: "Traffic", parts: ["measuring…"])
                }
                StatRow(title: "Device", parts: [wired.device, wired.ipv4])
                StatRow(title: "Gateway", parts: [wired.gateway])
                StatRow(title: "Upstream", parts: [wired.upstream])
            } else {
                StatRow(title: "Link", parts: ["no cable"])
                StatRow(title: "Device", parts: [wired.device])
            }
        }
    }
}
