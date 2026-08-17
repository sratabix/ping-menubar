import Foundation

struct ProbeOutcome: Equatable {
    var rtt: TimeInterval?
    var mode: ProbeMode
    var dnsFailing: Bool
    var address: String?
    var detail: String?
}

final class PingSession: @unchecked Sendable {
    struct Config: Equatable {
        var host: String
        var timeout: TimeInterval
        var tcpPort: UInt16
    }

    static let icmpPatience = 3
    static let icmpRetryCycles = 20

    var resolve: (String) -> Result<Endpoint, ProbeFailure> = Resolver.resolve
    var icmp: (Endpoint, UInt16, TimeInterval) -> Result<TimeInterval, ProbeFailure> = ICMPProbe.ping
    var tcp: (Endpoint, UInt16, TimeInterval) -> Result<TimeInterval, ProbeFailure> = TCPProbe.connect

    private(set) var mode: ProbeMode = .icmp
    private var sequence: UInt16 = 0
    private var icmpFailures = 0
    private var cyclesSinceICMPRetry = 0
    private var cached: (host: String, endpoint: Endpoint)?

    func reset() {
        mode = .icmp
        icmpFailures = 0
        cyclesSinceICMPRetry = 0
        cached = nil
    }

    func run(_ config: Config) -> ProbeOutcome {
        var dnsFailing = false
        var endpoint: Endpoint
        switch resolve(config.host) {
        case .success(let resolved):
            endpoint = resolved
            cached = (config.host, resolved)
        case .failure(let failure):
            dnsFailing = true
            guard let cached, cached.host == config.host else {
                return ProbeOutcome(rtt: nil, mode: mode, dnsFailing: true, address: nil, detail: describe(failure))
            }
            endpoint = cached.endpoint
        }

        sequence &+= 1
        var detail: String?

        if mode == .tcp {
            cyclesSinceICMPRetry += 1
            if cyclesSinceICMPRetry >= Self.icmpRetryCycles {
                cyclesSinceICMPRetry = 0
                if case .success(let rtt) = icmp(endpoint, sequence, config.timeout) {
                    mode = .icmp
                    icmpFailures = 0
                    return ProbeOutcome(
                        rtt: rtt, mode: .icmp, dnsFailing: dnsFailing, address: endpoint.text, detail: nil)
                }
            }
        } else {
            switch icmp(endpoint, sequence, config.timeout) {
            case .success(let rtt):
                icmpFailures = 0
                return ProbeOutcome(rtt: rtt, mode: .icmp, dnsFailing: dnsFailing, address: endpoint.text, detail: nil)
            case .failure(let failure):
                icmpFailures += 1
                detail = describe(failure)
                let blocked = icmpFailures >= Self.icmpPatience || isFatal(failure)
                guard blocked else {
                    return ProbeOutcome(
                        rtt: nil, mode: .icmp, dnsFailing: dnsFailing, address: endpoint.text, detail: detail)
                }
            }
        }

        switch tcp(endpoint, config.tcpPort, config.timeout) {
        case .success(let rtt):
            if mode == .icmp {
                mode = .tcp
                cyclesSinceICMPRetry = 0
            }
            return ProbeOutcome(rtt: rtt, mode: .tcp, dnsFailing: dnsFailing, address: endpoint.text, detail: nil)
        case .failure(let failure):
            return ProbeOutcome(
                rtt: nil,
                mode: mode,
                dnsFailing: dnsFailing,
                address: endpoint.text,
                detail: detail ?? describe(failure)
            )
        }
    }

    private func isFatal(_ failure: ProbeFailure) -> Bool {
        switch failure {
        case .socket, .unreachable: return true
        case .timeout, .dns: return false
        }
    }

    private func describe(_ failure: ProbeFailure) -> String {
        switch failure {
        case .dns(let message): return "DNS: \(message)"
        case .unreachable(let message): return message
        case .socket(let message): return message
        case .timeout: return "timed out"
        }
    }
}
