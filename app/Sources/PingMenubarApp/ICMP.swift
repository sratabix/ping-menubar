import Foundation

enum ICMPPacket {
    static let headerLength = 8
    static let tokenLength = 8
    static let payloadLength = 16

    enum Kind: UInt8 {
        case echoRequestV4 = 8
        case echoReplyV4 = 0
        case echoRequestV6 = 128
        case echoReplyV6 = 129
    }

    struct Reply: Equatable {
        var sequence: UInt16
        var token: UInt64
    }

    static func echoRequest(isIPv6: Bool, identifier: UInt16, sequence: UInt16, token: UInt64) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: headerLength + payloadLength)
        packet[0] = (isIPv6 ? Kind.echoRequestV6 : Kind.echoRequestV4).rawValue
        packet[1] = 0
        write(identifier, into: &packet, at: 4)
        write(sequence, into: &packet, at: 6)
        write(token, into: &packet, at: headerLength)
        for index in (headerLength + tokenLength)..<packet.count {
            packet[index] = UInt8(index & 0xFF)
        }
        if !isIPv6 {
            write(checksum(packet), into: &packet, at: 2)
        }
        return packet
    }

    static func parseReply(_ bytes: [UInt8], isIPv6: Bool) -> Reply? {
        var body = bytes[...]
        if !isIPv6, let first = body.first, first >> 4 == 4 {
            let headerBytes = Int(first & 0x0F) * 4
            guard body.count > headerBytes else { return nil }
            body = body.dropFirst(headerBytes)
        }
        guard body.count >= headerLength + tokenLength else { return nil }
        let payload = Array(body)
        let expected = (isIPv6 ? Kind.echoReplyV6 : Kind.echoReplyV4).rawValue
        guard payload[0] == expected else { return nil }
        return Reply(
            sequence: read(payload, at: 6),
            token: read(payload, at: headerLength)
        )
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum &+= UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum &+= UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return UInt16(truncatingIfNeeded: ~sum)
    }

    private static func write(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
    }

    private static func write(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
        for byte in 0..<8 {
            bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> (56 - byte * 8))
        }
    }

    private static func read(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func read(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in 0..<8 {
            value = value << 8 | UInt64(bytes[offset + byte])
        }
        return value
    }
}

enum ICMPProbe {
    static func ping(_ endpoint: Endpoint, sequence: UInt16, timeout: TimeInterval) -> Result<
        TimeInterval, ProbeFailure
    > {
        let proto = endpoint.isIPv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
        let descriptor = socket(endpoint.family, SOCK_DGRAM, proto)
        guard descriptor >= 0 else { return .failure(.socket(Errno.describe())) }
        defer { close(descriptor) }

        let token = UInt64.random(in: 1...UInt64.max)
        let packet = ICMPPacket.echoRequest(
            isIPv6: endpoint.isIPv6,
            identifier: UInt16(truncatingIfNeeded: getpid()),
            sequence: sequence,
            token: token
        )

        let started = Clock.now()
        let sent = endpoint.withSocketAddress { address, length in
            sendto(descriptor, packet, packet.count, 0, address, length)
        }
        guard sent == packet.count else { return .failure(.unreachable(Errno.describe())) }

        var buffer = [UInt8](repeating: 0, count: 1500)
        let deadline = started + timeout
        while true {
            let remaining = deadline - Clock.now()
            guard remaining > 0 else { return .failure(.timeout) }

            var descriptors = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptors, 1, Int32((remaining * 1000).rounded(.up)))
            if ready < 0 {
                guard errno == EINTR else { return .failure(.socket(Errno.describe())) }
                continue
            }
            guard ready > 0 else { return .failure(.timeout) }

            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count < 0 {
                guard errno == EINTR else { return .failure(.socket(Errno.describe())) }
                continue
            }
            let elapsed = Clock.now() - started
            guard
                let reply = ICMPPacket.parseReply(Array(buffer[0..<count]), isIPv6: endpoint.isIPv6),
                reply.token == token,
                reply.sequence == sequence
            else { continue }
            return .success(elapsed)
        }
    }
}

enum Errno {
    static func describe(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }
}

enum Clock {
    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
}
