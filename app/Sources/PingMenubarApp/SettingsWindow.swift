import Combine
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var draftHost: String = ""

    static let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Host").font(.callout)
                TextField("1.1.1.1", text: $draftHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitHost() }
                note("An IP or a domain. Changing it clears the current statistics.")
            }
            Divider()
            stepper(
                "Interval",
                value: $model.interval,
                range: Preferences.intervalRange,
                step: 0.5,
                unit: "s",
                note: "How often to probe.")
            stepper(
                "Timeout",
                value: $model.timeout,
                range: Preferences.timeoutRange,
                step: 0.5,
                unit: "s",
                note: "A probe with no reply in this window counts as lost.")
            stepper(
                "Slow above",
                value: $model.warnThreshold,
                range: Preferences.warnRange,
                step: 0.01,
                unit: "ms",
                scale: 1000,
                note: "The dot turns orange past this latency.")
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Fallback port").font(.callout)
                    Spacer()
                    TextField("443", value: $model.tcpPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                note("When ICMP is blocked the app times a TCP handshake to this port instead.")
            }
            Divider()
            toggle(
                "Show the status dot",
                note: "A coloured dot left of the number: green, orange, yellow for DNS, red for offline.",
                isOn: $model.showDot)
            toggle(
                "Launch app at login",
                note: "PingMenubar starts with macOS and waits in the menubar.",
                isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.launchAtLoginError {
                note(error, colour: .orange)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    commitHost()
                    model.closeSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: SettingsView.width)
        .onAppear { draftHost = model.host }
    }

    private func commitHost() {
        let trimmed = draftHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            draftHost = model.host
            return
        }
        model.host = trimmed
    }

    private func stepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        scale: Double = 1,
        note text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(display(value.wrappedValue * scale, unit: unit))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(
                    title,
                    value: value,
                    in: range,
                    step: step
                )
                .labelsHidden()
            }
            note(text)
        }
    }

    private func display(_ value: Double, unit: String) -> String {
        let rounded = (value * 100).rounded() / 100
        let text =
            rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "\(text) \(unit)"
    }

    private func toggle(_ title: String, note text: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn).toggleStyle(.checkbox).font(.callout)
            note(text)
        }
    }

    private func note(_ text: String, colour: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
final class SettingsWindowPresenter {
    private weak var model: AppModel?
    private let host = WindowHost()
    private var watch: AnyCancellable?

    func attach(to model: AppModel) {
        self.model = model
        host.onClose = { [weak model] in model?.closeSettings() }
        watch =
            model.$showingSettings
            .removeDuplicates()
            .sink { [weak self] showing in
                Task { @MainActor in
                    guard let self else { return }
                    showing ? self.show() : self.host.hide()
                }
            }
    }

    private func show() {
        guard let model else { return }
        host.show(title: "PingMenubar Settings") {
            SettingsView().environmentObject(model)
        }
    }
}
