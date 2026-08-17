import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: PingState = .waiting
    @Published private(set) var samples = Samples()
    @Published private(set) var mode: ProbeMode = .icmp
    @Published private(set) var address: String?
    @Published private(set) var detail: String?
    @Published private(set) var label: NSImage = MenuBarLabel.image(for: .waiting)

    @Published var showingSettings = false
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var launchAtLoginError: String?

    @Published private(set) var wifi: WiFiSnapshot?
    @Published private(set) var wired: [WiredSnapshot] = []
    @Published private(set) var wifiLog: [LogEntry] = []
    @Published var wifiExpanded: Bool = Preferences.wifiExpanded {
        didSet { Preferences.wifiExpanded = wifiExpanded }
    }
    @Published var wiredExpanded: Bool = Preferences.wiredExpanded {
        didSet { Preferences.wiredExpanded = wiredExpanded }
    }

    @Published var host: String = Preferences.host {
        didSet {
            Preferences.host = host
            if host != oldValue { restart() }
        }
    }
    @Published var interval: Double = Preferences.interval {
        didSet { Preferences.interval = interval }
    }
    @Published var timeout: Double = Preferences.timeout {
        didSet { Preferences.timeout = timeout }
    }
    @Published var warnThreshold: Double = Preferences.warnThreshold {
        didSet {
            Preferences.warnThreshold = warnThreshold
            refresh()
        }
    }
    @Published var tcpPort: Int = Preferences.tcpPort {
        didSet { Preferences.tcpPort = tcpPort }
    }
    @Published var showDot: Bool = Preferences.showDot {
        didSet {
            Preferences.showDot = showDot
            render()
        }
    }

    static let detailRefresh: Duration = .seconds(2)
    static let idleDetailRefresh: Duration = .seconds(10)

    private let session = PingSession()
    private let monitor = NetworkMonitor()
    private let settings = SettingsWindowPresenter()
    private let wifiMonitor = WiFiMonitor()
    private let wiredMonitor = WiredMonitor()
    private var detailLoop: Task<Void, Never>?
    private var detailVisible = false
    private var loggedID = 0
    private var loop: Task<Void, Never>?
    private var failureStreak = 0
    private var dnsFailing = false
    private var theme: (any NSObjectProtocol)?

    init() {
        settings.attach(to: self)
        monitor.onChange = { [weak self] satisfied in
            guard let self else { return }
            self.refresh()
            if satisfied { self.restart() }
        }
        monitor.start()
        startNetworkDetail()
        theme = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        restart()
    }

    var policy: StatusPolicy {
        StatusPolicy(warn: warnThreshold, failuresBeforeOffline: 2)
    }

    var reachable: Bool { monitor.satisfied }

    func restart() {
        loop?.cancel()
        session.reset()
        samples.clear()
        failureStreak = 0
        dnsFailing = false
        refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let wait = self.interval
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func tick() async {
        guard monitor.satisfied else {
            refresh()
            return
        }
        let config = PingSession.Config(host: host, timeout: timeout, tcpPort: UInt16(tcpPort))
        let session = self.session
        let outcome = await Task.detached(priority: .utility) { session.run(config) }.value

        samples.append(outcome.rtt)
        failureStreak = outcome.rtt == nil ? failureStreak + 1 : 0
        dnsFailing = outcome.dnsFailing
        mode = outcome.mode
        address = outcome.address
        detail = outcome.rtt == nil ? outcome.detail : nil
        refresh()
    }

    private func refresh() {
        state = policy.state(
            latest: samples.lastReceived,
            failureStreak: failureStreak,
            dnsFailing: dnsFailing,
            pathSatisfied: monitor.satisfied
        )
        render()
    }

    private func render() {
        label = MenuBarLabel.image(for: state, showDot: showDot)
    }

    func showNetworkDetail() {
        detailVisible = true
        sampleNetworkDetail()
    }

    func hideNetworkDetail() {
        detailVisible = false
    }

    private func startNetworkDetail() {
        guard detailLoop == nil else { return }
        sampleNetworkDetail()
        detailLoop = Task { [weak self] in
            while !Task.isCancelled {
                let wait = self?.detailVisible == true ? AppModel.detailRefresh : AppModel.idleDetailRefresh
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                self.sampleNetworkDetail()
            }
        }
    }

    private func sampleNetworkDetail() {
        let previous = wifi
        let current = wifiMonitor.snapshot()
        wifi = current
        wired = wiredMonitor.snapshots()

        let changes = WiFiLog.changes(from: previous, to: current)
        wifiLog = WiFiLog.append(changes, to: wifiLog, at: Date(), nextID: loggedID)
        loggedID += changes.count
    }

    func openSettings() {
        showingSettings = true
    }

    func closeSettings() {
        showingSettings = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = LaunchAtLogin.set(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
