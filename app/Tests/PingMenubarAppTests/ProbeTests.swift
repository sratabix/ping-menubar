import Foundation
import TestKit

@testable import PingMenubarApp

private let unroutedTestNet = "192.0.2.1"

private func endpoint(_ host: String) -> Endpoint? {
    guard case .success(let endpoint) = Resolver.resolve(host) else { return nil }
    return endpoint
}

final class ICMPProbeTests: TestCase {
    func testLoopbackAnswersItsOwnEcho() {
        guard let endpoint = endpoint("127.0.0.1") else { return fail("127.0.0.1 should resolve") }
        switch ICMPProbe.ping(endpoint, sequence: 1, timeout: 2) {
        case .success(let rtt):
            expectAtLeast(rtt, 0)
            expectLessThan(rtt, 2)
        case .failure(.socket(let message)):
            skip("no unprivileged ICMP socket here: \(message)")
        case .failure(let failure):
            fail("loopback should answer, got \(failure)")
        }
    }

    func testEachProbeUsesAFreshSocket() {
        guard let endpoint = endpoint("127.0.0.1") else { return fail("127.0.0.1 should resolve") }
        for sequence in UInt16(1)...5 {
            if case .failure(.socket(let message)) = ICMPProbe.ping(endpoint, sequence: sequence, timeout: 2) {
                return skip("no unprivileged ICMP socket here: \(message)")
            }
        }
    }

    func testAnUnroutedAddressTimesOut() {
        guard let endpoint = endpoint(unroutedTestNet) else { return fail("\(unroutedTestNet) should resolve") }
        switch ICMPProbe.ping(endpoint, sequence: 1, timeout: 0.3) {
        case .success:
            fail("TEST-NET-1 must not answer")
        case .failure(.socket(let message)):
            skip("no unprivileged ICMP socket here: \(message)")
        case .failure:
            break
        }
    }

    func testTheTimeoutIsRespected() {
        guard let endpoint = endpoint(unroutedTestNet) else { return fail("\(unroutedTestNet) should resolve") }
        let started = Clock.now()
        if case .failure(.socket) = ICMPProbe.ping(endpoint, sequence: 1, timeout: 0.3) {
            return skip("no unprivileged ICMP socket here")
        }
        expectLessThan(Clock.now() - started, 2, "a 0.3s timeout must not block for seconds")
    }
}

final class TCPProbeTests: TestCase {
    func testARefusedConnectionStillProvesTheRoundTrip() {
        guard let endpoint = endpoint("127.0.0.1") else { return fail("127.0.0.1 should resolve") }
        switch TCPProbe.connect(endpoint, port: 9, timeout: 2) {
        case .success(let rtt):
            expectAtLeast(rtt, 0)
        case .failure(let failure):
            fail("a refused loopback port is reachable, got \(failure)")
        }
    }

    func testAnUnroutedAddressFails() {
        guard let endpoint = endpoint(unroutedTestNet) else { return fail("\(unroutedTestNet) should resolve") }
        switch TCPProbe.connect(endpoint, port: 443, timeout: 0.3) {
        case .success:
            fail("TEST-NET-1 must not connect")
        case .failure:
            break
        }
    }

    func testTheTimeoutIsRespected() {
        guard let endpoint = endpoint(unroutedTestNet) else { return fail("\(unroutedTestNet) should resolve") }
        let started = Clock.now()
        _ = TCPProbe.connect(endpoint, port: 443, timeout: 0.3)
        expectLessThan(Clock.now() - started, 2)
    }
}

final class ClockTests: TestCase {
    func testTheClockMovesForward() {
        let first = Clock.now()
        let second = Clock.now()
        expectAtLeast(second, first)
    }

    func testTheClockIsInSeconds() {
        let started = Clock.now()
        usleep(120_000)
        let elapsed = Clock.now() - started
        expectGreaterThan(elapsed, 0.05)
        expectLessThan(elapsed, 2)
    }
}

final class ErrnoTests: TestCase {
    func testKnownCodesAreDescribed() {
        expectEqual(Errno.describe(ECONNREFUSED), "Connection refused")
        expectEqual(Errno.describe(ETIMEDOUT), "Operation timed out")
    }
}
