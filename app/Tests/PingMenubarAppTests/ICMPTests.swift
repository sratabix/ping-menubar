import Foundation
import TestKit

@testable import PingMenubarApp

final class ICMPChecksumTests: TestCase {
    func testKnownPacket() {
        expectEqual(ICMPPacket.checksum([8, 0, 0, 0, 0x12, 0x34, 0x00, 0x01]), 0xE5CA)
    }

    func testOddLengthPadsTheFinalByte() {
        expectEqual(ICMPPacket.checksum([0x01]), 0xFEFF)
    }

    func testEmptyInput() {
        expectEqual(ICMPPacket.checksum([]), 0xFFFF)
    }

    func testAllOnesFoldsToZero() {
        expectEqual(ICMPPacket.checksum([0xFF, 0xFF]), 0)
    }

    func testCarriesAreFoldedBackIn() {
        expectEqual(ICMPPacket.checksum([0xFF, 0xFF, 0xFF, 0xFF]), 0)
    }

    func testAPacketWithItsChecksumSumsToZero() {
        let packet = ICMPPacket.echoRequest(isIPv6: false, identifier: 7, sequence: 9, token: 0x1234_5678)
        expectEqual(ICMPPacket.checksum(packet), 0)
    }

    func testAnyCorruptionBreaksTheChecksum() {
        let packet = ICMPPacket.echoRequest(isIPv6: false, identifier: 7, sequence: 9, token: 0x1234_5678)
        for index in packet.indices where index != 2 && index != 3 {
            var corrupt = packet
            corrupt[index] ^= 0xFF
            expectNotEqual(ICMPPacket.checksum(corrupt), 0, "byte \(index) must be covered")
        }
    }
}

final class ICMPPacketTests: TestCase {
    func testEchoRequestHeader() {
        let packet = ICMPPacket.echoRequest(
            isIPv6: false, identifier: 0x1234, sequence: 7, token: 0xDEAD_BEEF_CAFE_0001)
        expectEqual(packet.count, 24)
        expectEqual(packet[0], 8)
        expectEqual(packet[1], 0)
        expectEqual(packet[4], 0x12)
        expectEqual(packet[5], 0x34)
        expectEqual(packet[6], 0)
        expectEqual(packet[7], 7)
    }

    func testSequenceUsesBothBytes() {
        let packet = ICMPPacket.echoRequest(isIPv6: false, identifier: 1, sequence: 0x0102, token: 0)
        expectEqual(packet[6], 0x01)
        expectEqual(packet[7], 0x02)
    }

    func testTokenIsWrittenBigEndian() {
        let packet = ICMPPacket.echoRequest(isIPv6: true, identifier: 1, sequence: 1, token: 0x0102_0304_0506_0708)
        expectEqual(Array(packet[8..<16]), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testIPv6UsesTheEchoRequestTypeAndNoChecksum() {
        let packet = ICMPPacket.echoRequest(isIPv6: true, identifier: 1, sequence: 1, token: 42)
        expectEqual(packet[0], 128)
        expectEqual(packet[2], 0)
        expectEqual(packet[3], 0)
    }

    func testIPv4CarriesAComputedChecksum() {
        let packet = ICMPPacket.echoRequest(isIPv6: false, identifier: 1, sequence: 1, token: 42)
        expectNotEqual(packet[2] | packet[3], 0)
    }

    func testRoundTripThroughAReply() {
        var reply = ICMPPacket.echoRequest(isIPv6: false, identifier: 3, sequence: 513, token: 0xABCD_EF01)
        reply[0] = 0
        expectEqual(
            ICMPPacket.parseReply(reply, isIPv6: false),
            ICMPPacket.Reply(sequence: 513, token: 0xABCD_EF01))
    }

    func testIPv4HeaderIsStrippedUsingItsLengthField() {
        var reply = ICMPPacket.echoRequest(isIPv6: false, identifier: 1, sequence: 9, token: 0xAABB)
        reply[0] = 0
        for words in 5...8 {
            let header = [UInt8(0x40 | words)] + [UInt8](repeating: 0, count: words * 4 - 1)
            expectEqual(
                ICMPPacket.parseReply(header + reply, isIPv6: false),
                ICMPPacket.Reply(sequence: 9, token: 0xAABB),
                "a \(words * 4) byte IP header must be skipped")
        }
    }

    func testIPv6RepliesCarryNoIPHeader() {
        var reply = ICMPPacket.echoRequest(isIPv6: true, identifier: 1, sequence: 3, token: 5)
        reply[0] = 129
        expectEqual(ICMPPacket.parseReply(reply, isIPv6: true), ICMPPacket.Reply(sequence: 3, token: 5))
    }

    func testEchoRequestsAreNotMistakenForReplies() {
        let request = ICMPPacket.echoRequest(isIPv6: false, identifier: 1, sequence: 1, token: 1)
        expectNil(ICMPPacket.parseReply(request, isIPv6: false))
    }

    func testTheWrongFamilyIsRejected() {
        var reply = ICMPPacket.echoRequest(isIPv6: true, identifier: 1, sequence: 1, token: 1)
        reply[0] = 129
        expectNil(ICMPPacket.parseReply(reply, isIPv6: false))
    }

    func testShortPacketsAreRejected() {
        expectNil(ICMPPacket.parseReply([], isIPv6: true))
        expectNil(ICMPPacket.parseReply([0, 0, 0, 0], isIPv6: true))
        expectNil(ICMPPacket.parseReply([UInt8](repeating: 0, count: 15), isIPv6: true))
    }

    func testATruncatedIPv4HeaderIsRejected() {
        expectNil(ICMPPacket.parseReply([0x45, 0, 0, 0], isIPv6: false))
    }

    func testDestinationUnreachableIsNotAReply() {
        var packet = ICMPPacket.echoRequest(isIPv6: false, identifier: 1, sequence: 1, token: 1)
        packet[0] = 3
        expectNil(ICMPPacket.parseReply(packet, isIPv6: false))
    }
}
