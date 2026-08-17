import Foundation
import TestKit

@testable import PingMenubarApp

extension Endpoint {
    static func stub(_ text: String = "203.0.113.7") -> Endpoint {
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { raw in
            raw.storeBytes(of: UInt8(MemoryLayout<sockaddr_in>.size), toByteOffset: 0, as: UInt8.self)
            raw.storeBytes(of: UInt8(AF_INET), toByteOffset: 1, as: UInt8.self)
        }
        return Endpoint(
            family: AF_INET,
            address: storage,
            length: socklen_t(MemoryLayout<sockaddr_in>.size),
            text: text)
    }
}

final class PingSessionTests: TestCase {
    private let config = PingSession.Config(host: "example.test", timeout: 1, tcpPort: 443)

    private func session(
        resolve: @escaping (String) -> Result<Endpoint, ProbeFailure> = { _ in .success(.stub()) },
        icmp: @escaping (Endpoint, UInt16, TimeInterval) -> Result<TimeInterval, ProbeFailure>,
        tcp: @escaping (Endpoint, UInt16, TimeInterval) -> Result<TimeInterval, ProbeFailure> = { _, _, _ in
            .failure(.timeout)
        }
    ) -> PingSession {
        let session = PingSession()
        session.resolve = resolve
        session.icmp = icmp
        session.tcp = tcp
        return session
    }

    func testAnICMPReplyIsReportedDirectly() {
        let outcome = session(icmp: { _, _, _ in .success(0.012) }).run(config)
        expectEqual(outcome.rtt, 0.012)
        expectEqual(outcome.mode, .icmp)
        expectEqual(outcome.address, "203.0.113.7")
        expectFalse(outcome.dnsFailing)
        expectNil(outcome.detail)
    }

    func testASessionStartsOnICMP() {
        expectEqual(PingSession().mode, .icmp)
    }

    func testTheSequenceAdvancesEveryCycle() {
        var seen: [UInt16] = []
        let session = session(icmp: { _, sequence, _ in
            seen.append(sequence)
            return .success(0.01)
        })
        for _ in 0..<3 { _ = session.run(config) }
        expectEqual(seen, [1, 2, 3])
    }

    func testTheConfiguredTimeoutReachesTheProbe() {
        var seen: TimeInterval?
        let session = session(icmp: { _, _, timeout in
            seen = timeout
            return .success(0.01)
        })
        _ = session.run(PingSession.Config(host: "example.test", timeout: 4.5, tcpPort: 443))
        expectEqual(seen, 4.5)
    }

    func testTheConfiguredPortReachesTheFallback() {
        var seen: UInt16?
        let session = session(
            icmp: { _, _, _ in .failure(.socket("blocked")) },
            tcp: { _, port, _ in
                seen = port
                return .success(0.05)
            })
        _ = session.run(PingSession.Config(host: "example.test", timeout: 1, tcpPort: 8080))
        expectEqual(seen, 8080)
    }

    func testOccasionalICMPLossDoesNotSwitchToTCP() {
        var tcpCalls = 0
        let session = session(
            icmp: { _, _, _ in .failure(.timeout) },
            tcp: { _, _, _ in
                tcpCalls += 1
                return .success(0.05)
            })
        let outcome = session.run(config)
        expectNil(outcome.rtt)
        expectEqual(outcome.mode, .icmp)
        expectEqual(outcome.detail, "timed out")
        expectEqual(tcpCalls, 0)
    }

    func testICMPFallsBackToTCPAfterRepeatedSilence() {
        let session = session(
            icmp: { _, _, _ in .failure(.timeout) },
            tcp: { _, _, _ in .success(0.05) })
        for _ in 0..<(PingSession.icmpPatience - 1) { _ = session.run(config) }
        let outcome = session.run(config)
        expectEqual(outcome.rtt, 0.05)
        expectEqual(outcome.mode, .tcp)
        expectEqual(session.mode, .tcp)
    }

    func testAReplyBeforePatienceRunsOutResetsTheStreak() {
        var replies = [false, false, true, false, false]
        var index = 0
        var tcpCalls = 0
        let session = session(
            icmp: { _, _, _ in
                defer { index += 1 }
                return replies[index] ? .success(0.01) : .failure(.timeout)
            },
            tcp: { _, _, _ in
                tcpCalls += 1
                return .success(0.05)
            })
        for _ in 0..<replies.count { _ = session.run(config) }
        expectEqual(session.mode, .icmp)
        expectEqual(tcpCalls, 0)
        replies = []
    }

    func testABlockedICMPSocketFallsBackImmediately() {
        let outcome = session(
            icmp: { _, _, _ in .failure(.socket("permission denied")) },
            tcp: { _, _, _ in .success(0.07) }
        ).run(config)
        expectEqual(outcome.mode, .tcp)
        expectEqual(outcome.rtt, 0.07)
    }

    func testAnUnreachableNetworkFallsBackImmediately() {
        let outcome = session(
            icmp: { _, _, _ in .failure(.unreachable("No route to host")) },
            tcp: { _, _, _ in .success(0.07) }
        ).run(config)
        expectEqual(outcome.mode, .tcp)
    }

    func testTCPModeRetriesICMPAndSwitchesBack() {
        var icmpWorks = false
        let session = session(
            icmp: { _, _, _ in icmpWorks ? .success(0.011) : .failure(.socket("blocked")) },
            tcp: { _, _, _ in .success(0.05) })

        _ = session.run(config)
        expectEqual(session.mode, .tcp)
        icmpWorks = true

        for _ in 0..<(PingSession.icmpRetryCycles - 1) {
            expectEqual(session.run(config).mode, .tcp)
        }
        let outcome = session.run(config)
        expectEqual(outcome.mode, .icmp)
        expectEqual(outcome.rtt, 0.011)
    }

    func testTCPModeStaysOnTCPWhileICMPKeepsFailing() {
        let session = session(
            icmp: { _, _, _ in .failure(.socket("blocked")) },
            tcp: { _, _, _ in .success(0.05) })
        for _ in 0..<(PingSession.icmpRetryCycles + 5) { _ = session.run(config) }
        expectEqual(session.mode, .tcp)
    }

    func testADNSFailureWithoutACachedAddressReportsNoProbe() {
        let outcome = session(
            resolve: { _ in .failure(.dns("nodename nor servname provided")) },
            icmp: { _, _, _ in .success(0.01) }
        ).run(config)
        expectNil(outcome.rtt)
        expectTrue(outcome.dnsFailing)
        expectNil(outcome.address)
        expectEqual(outcome.detail, "DNS: nodename nor servname provided")
    }

    func testADNSFailureKeepsPingingTheCachedAddress() {
        var resolves = true
        let session = session(
            resolve: { _ in resolves ? .success(.stub()) : .failure(.dns("timed out")) },
            icmp: { _, _, _ in .success(0.02) })

        expectFalse(session.run(config).dnsFailing)
        resolves = false
        let outcome = session.run(config)
        expectEqual(outcome.rtt, 0.02)
        expectTrue(outcome.dnsFailing)
        expectEqual(outcome.address, "203.0.113.7")
    }

    func testACachedAddressIsNotReusedForADifferentHost() {
        var resolves = true
        let session = session(
            resolve: { _ in resolves ? .success(.stub()) : .failure(.dns("timed out")) },
            icmp: { _, _, _ in .success(0.02) })
        _ = session.run(config)
        resolves = false

        let other = PingSession.Config(host: "elsewhere.test", timeout: 1, tcpPort: 443)
        let outcome = session.run(other)
        expectNil(outcome.rtt)
        expectNil(outcome.address)
    }

    func testEverythingDownReportsTheICMPDetail() {
        let outcome = session(
            icmp: { _, _, _ in .failure(.unreachable("No route to host")) },
            tcp: { _, _, _ in .failure(.timeout) }
        ).run(config)
        expectNil(outcome.rtt)
        expectEqual(outcome.detail, "No route to host")
    }

    func testResetReturnsToICMPAndForgetsTheCache() {
        let session = session(
            icmp: { _, _, _ in .failure(.socket("blocked")) },
            tcp: { _, _, _ in .success(0.05) })
        _ = session.run(config)
        expectEqual(session.mode, .tcp)

        session.reset()
        expectEqual(session.mode, .icmp)
    }

    func testResetRestartsTheSequence() {
        var seen: [UInt16] = []
        let session = session(icmp: { _, sequence, _ in
            seen.append(sequence)
            return .success(0.01)
        })
        _ = session.run(config)
        session.reset()
        _ = session.run(config)
        expectEqual(seen.count, 2)
    }
}

final class ProbeFailureTests: TestCase {
    func testFailuresCompareByCase() {
        expectEqual(ProbeFailure.timeout, .timeout)
        expectEqual(ProbeFailure.dns("a"), .dns("a"))
        expectNotEqual(ProbeFailure.dns("a"), .dns("b"))
        expectNotEqual(ProbeFailure.timeout, .socket("x"))
    }
}
