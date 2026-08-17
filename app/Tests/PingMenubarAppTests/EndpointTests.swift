import Foundation
import TestKit

@testable import PingMenubarApp

final class ResolverTests: TestCase {
    func testLiteralIPv4NeedsNoNameService() {
        guard let endpoint = resolved("127.0.0.1") else { return }
        expectEqual(endpoint.family, AF_INET)
        expectEqual(endpoint.text, "127.0.0.1")
        expectFalse(endpoint.isIPv6)
    }

    func testLiteralIPv6IsRecognised() {
        guard let endpoint = resolved("::1") else { return }
        expectEqual(endpoint.family, AF_INET6)
        expectTrue(endpoint.isIPv6)
        expectEqual(endpoint.text, "::1")
    }

    func testIPv4IsPreferredOverIPv6() {
        guard let endpoint = resolved("localhost") else { return }
        expectEqual(endpoint.family, AF_INET, "ICMPv4 is the more reliable probe")
    }

    func testEmptyHostIsADNSFailure() {
        assertDNSFailure(Resolver.resolve(""), message: "no host configured")
    }

    func testWhitespaceOnlyHostIsADNSFailure() {
        assertDNSFailure(Resolver.resolve("   "), message: "no host configured")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        expectEqual(resolved("  127.0.0.1 ")?.text, "127.0.0.1")
    }

    func testUnresolvableHostIsADNSFailure() {
        guard case .failure(let failure) = Resolver.resolve("no-such-host.invalid") else {
            return fail("a bogus host must not resolve")
        }
        guard case .dns = failure else {
            return fail("expected a DNS failure, got \(failure)")
        }
    }

    private func resolved(_ host: String, file: StaticString = #filePath, line: UInt = #line) -> Endpoint? {
        guard case .success(let endpoint) = Resolver.resolve(host) else {
            fail("\(host) should resolve", file: file, line: line)
            return nil
        }
        return endpoint
    }

    private func assertDNSFailure(
        _ result: Result<Endpoint, ProbeFailure>,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let failure) = result else {
            return fail("expected a failure", file: file, line: line)
        }
        expectEqual(failure, .dns(message), file: file, line: line)
    }
}

final class EndpointTests: TestCase {
    func testWithPortWritesTheIPv4Port() {
        guard let endpoint = literal("127.0.0.1")?.withPort(8443) else { return }
        expectEqual(port(of: endpoint), 8443)
    }

    func testWithPortWritesTheIPv6Port() {
        guard let endpoint = literal("::1")?.withPort(8443) else { return }
        expectEqual(port(of: endpoint), 8443)
    }

    func testWithPortLeavesTheAddressAlone() {
        guard let original = literal("127.0.0.1") else { return }
        let ported = original.withPort(443)
        expectEqual(ported.text, original.text)
        expectEqual(ported.family, original.family)
    }

    func testEndpointsAreEqualByFamilyAndAddress() {
        guard let first = literal("127.0.0.1"), let second = literal("127.0.0.1") else { return }
        expectEqual(first, second)
        expectNotEqual(first, literal("::1"))
    }

    func testSocketAddressIsHandedOutWithItsLength() {
        guard let endpoint = literal("127.0.0.1") else { return }
        let length = endpoint.withSocketAddress { _, length in length }
        expectEqual(length, socklen_t(MemoryLayout<sockaddr_in>.size))
    }

    private func literal(_ host: String, file: StaticString = #filePath, line: UInt = #line) -> Endpoint? {
        guard case .success(let endpoint) = Resolver.resolve(host) else {
            fail("\(host) should resolve", file: file, line: line)
            return nil
        }
        return endpoint
    }

    private func port(of endpoint: Endpoint) -> UInt16 {
        let offset =
            endpoint.isIPv6
            ? MemoryLayout<sockaddr_in6>.offset(of: \.sin6_port)
            : MemoryLayout<sockaddr_in>.offset(of: \.sin_port)
        return withUnsafeBytes(of: endpoint.address) { raw in
            raw.loadUnaligned(fromByteOffset: offset ?? 2, as: UInt16.self).bigEndian
        }
    }
}
