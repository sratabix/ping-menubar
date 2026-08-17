import Foundation
import Network

@MainActor
final class NetworkMonitor {
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private var running = false

    private(set) var satisfied = true

    func start() {
        guard !running else { return }
        running = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.observe(satisfied) }
        }
        monitor.start(queue: .main)
    }

    func observe(_ current: Bool) {
        guard current != satisfied else { return }
        satisfied = current
        onChange?(current)
    }

    deinit {
        monitor.cancel()
    }
}
