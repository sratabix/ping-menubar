import CoreWLAN
import Foundation
import TestKit

@testable import PingMenubarApp

final class WiFiSnapshotTests: TestCase {
    private func snapshot(rssi: Int? = -59, noise: Int? = -91) -> WiFiSnapshot {
        var snapshot = WiFiSnapshot()
        snapshot.powered = true
        snapshot.rssi = rssi
        snapshot.noise = noise
        return snapshot
    }

    func testSNRIsTheGapBetweenSignalAndNoise() {
        expectEqual(snapshot().snr, 32)
        expectEqual(snapshot(rssi: -40, noise: -100).snr, 60)
    }

    func testSNRNeedsBothHalves() {
        expectNil(snapshot(noise: nil).snr)
        expectNil(snapshot(rssi: nil).snr)
        expectNil(snapshot(rssi: nil, noise: nil).snr)
    }

    func testQualityIsClampedToTheUsableRange() {
        expectEqual(snapshot(rssi: -40).quality, 1)
        expectEqual(snapshot(rssi: -50).quality, 1)
        expectEqual(snapshot(rssi: -100).quality, 0)
        expectEqual(snapshot(rssi: -110).quality, 0)
        expectEqual(snapshot(rssi: -75).quality ?? 0, 0.5, accuracy: 1e-9)
    }

    func testQualityIsMonotonic() {
        let strengths = [-40, -55, -65, -75, -85, -95]
        let qualities = strengths.map { snapshot(rssi: $0).quality ?? 0 }
        expectEqual(qualities, qualities.sorted(by: >))
    }

    func testQualityNeedsASignal() {
        expectNil(snapshot(rssi: nil).quality)
        expectNil(snapshot(rssi: nil).qualityLabel)
    }

    func testQualityLabelsFollowSignalStrength() {
        expectEqual(snapshot(rssi: -30).qualityLabel, "excellent")
        expectEqual(snapshot(rssi: -55).qualityLabel, "excellent")
        expectEqual(snapshot(rssi: -56).qualityLabel, "good")
        expectEqual(snapshot(rssi: -67).qualityLabel, "good")
        expectEqual(snapshot(rssi: -68).qualityLabel, "fair")
        expectEqual(snapshot(rssi: -75).qualityLabel, "fair")
        expectEqual(snapshot(rssi: -76).qualityLabel, "weak")
        expectEqual(snapshot(rssi: -95).qualityLabel, "weak")
    }

    func testAnEmptySnapshotIsUnpowered() {
        let empty = WiFiSnapshot()
        expectFalse(empty.powered)
        expectNil(empty.rssi)
        expectNil(empty.snr)
        expectNil(empty.quality)
    }
}

final class WiFiNamesTests: TestCase {
    func testRateSwitchesToGigabit() {
        expectEqual(WiFiNames.rate(54), "54 Mbps")
        expectEqual(WiFiNames.rate(867), "867 Mbps")
        expectEqual(WiFiNames.rate(999), "999 Mbps")
        expectEqual(WiFiNames.rate(1000), "1.00 Gbps")
        expectEqual(WiFiNames.rate(1297), "1.30 Gbps")
    }

    func testThroughputPicksAReadableUnit() {
        expectEqual(WiFiNames.throughput(0), "0 Kbps")
        expectEqual(WiFiNames.throughput(999), "0 Kbps")
        expectEqual(WiFiNames.throughput(1_000), "1 Kbps")
        expectEqual(WiFiNames.throughput(240_000), "240 Kbps")
        expectEqual(WiFiNames.throughput(1_600_000), "1.6 Mbps")
        expectEqual(WiFiNames.throughput(48_300_000), "48.3 Mbps")
        expectEqual(WiFiNames.throughput(2_400_000_000), "2.40 Gbps")
    }

    func testSixGigahertzAxIsLabelled6E() {
        expectEqual(WiFiNames.standard(.mode11ax, band: .band6GHz), "Wi-Fi 6E (802.11ax)")
        expectEqual(WiFiNames.standard(.mode11ax, band: .band5GHz), "Wi-Fi 6 (802.11ax)")
        expectEqual(WiFiNames.standard(.mode11ax, band: .band2GHz), "Wi-Fi 6 (802.11ax)")
    }

    func testOlderStandardsKeepTheirGeneration() {
        expectEqual(WiFiNames.standard(.mode11ac, band: .band5GHz), "Wi-Fi 5 (802.11ac)")
        expectEqual(WiFiNames.standard(.mode11n, band: .band2GHz), "Wi-Fi 4 (802.11n)")
        expectEqual(WiFiNames.standard(.mode11g, band: .band2GHz), "802.11g")
        expectEqual(WiFiNames.standard(.mode11b, band: .band2GHz), "802.11b")
        expectEqual(WiFiNames.standard(.mode11a, band: .band5GHz), "802.11a")
    }

    func testAnIdleRadioHasNoStandard() {
        expectNil(WiFiNames.standard(.modeNone, band: .bandUnknown))
    }

    func testChannelBands() {
        expectEqual(WiFiNames.band(.band2GHz), "2.4 GHz")
        expectEqual(WiFiNames.band(.band5GHz), "5 GHz")
        expectEqual(WiFiNames.band(.band6GHz), "6 GHz")
        expectNil(WiFiNames.band(.bandUnknown))
    }

    func testChannelWidths() {
        expectEqual(WiFiNames.width(.width20MHz), "20 MHz")
        expectEqual(WiFiNames.width(.width40MHz), "40 MHz")
        expectEqual(WiFiNames.width(.width80MHz), "80 MHz")
        expectEqual(WiFiNames.width(.width160MHz), "160 MHz")
        expectNil(WiFiNames.width(.widthUnknown))
    }

    func testSecurityNames() {
        expectEqual(WiFiNames.security(.none), "open")
        expectEqual(WiFiNames.security(.WEP), "WEP")
        expectEqual(WiFiNames.security(.wpa2Personal), "WPA2 Personal")
        expectEqual(WiFiNames.security(.wpa2Enterprise), "WPA2 Enterprise")
        expectEqual(WiFiNames.security(.wpa3Personal), "WPA3 Personal")
        expectEqual(WiFiNames.security(.wpa3Enterprise), "WPA3 Enterprise")
        expectEqual(WiFiNames.security(.wpa3Transition), "WPA2/WPA3")
        expectEqual(WiFiNames.security(.OWE), "Enhanced Open")
        expectNil(WiFiNames.security(.unknown))
    }
}

final class NetworkInterfacesTests: TestCase {
    func testLoopbackReportsCounters() {
        guard let counters = NetworkInterfaces.counters(of: "lo0") else {
            return fail("loopback should report counters")
        }
        expectGreaterThan(counters.input, 0)
    }

    func testCountersOnlyGrow() {
        guard let first = NetworkInterfaces.counters(of: "lo0"),
            let second = NetworkInterfaces.counters(of: "lo0")
        else {
            return fail("loopback should report counters")
        }
        expectAtLeast(second.input, first.input)
        expectAtLeast(second.output, first.output)
    }

    func testLoopbackHasItsAddress() {
        expectEqual(NetworkInterfaces.address(of: "lo0"), "127.0.0.1")
    }

    func testAnUnknownInterfaceHasNothing() {
        expectNil(NetworkInterfaces.counters(of: "nope99"))
        expectNil(NetworkInterfaces.address(of: "nope99"))
    }

    func testTheGlobalRouteIsReadable() {
        let global = NetworkInterfaces.globalIPv4()
        if let primary = global.primaryInterface {
            expectFalse(primary.isEmpty)
        }
    }

    func testAnInterfaceReportsItsOwnRouterNotThePrimaryOne() {
        let global = NetworkInterfaces.globalIPv4()
        guard let primary = global.primaryInterface else { return skip("no primary interface") }
        expectEqual(NetworkInterfaces.router(of: primary), global.router)
    }

    func testAnInterfaceWithoutAServiceHasNoRouter() {
        expectNil(NetworkInterfaces.router(of: "lo0"))
        expectNil(NetworkInterfaces.router(of: "nope99"))
    }
}

final class ARPTests: TestCase {
    private let mac = try! NSRegularExpression(pattern: "^[0-9a-f]{2}(:[0-9a-f]{2}){5}$")
    private let ipv4 = try! NSRegularExpression(pattern: "^([0-9]{1,3}\\.){3}[0-9]{1,3}$")

    private func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func testEveryEntryIsWellFormed() {
        let table = NetworkInterfaces.arpTable()
        guard !table.isEmpty else { return skip("the ARP table is empty on this machine") }
        for entry in table {
            expectTrue(matches(mac, entry.mac), "\(entry.mac) is not a MAC address")
            expectTrue(matches(ipv4, entry.ip), "\(entry.ip) is not an IPv4 address")
            expectGreaterThan(entry.index, 0)
        }
    }

    func testTheTableIsStableAcrossReads() {
        let table = NetworkInterfaces.arpTable()
        guard !table.isEmpty else { return skip("the ARP table is empty on this machine") }
        expectEqual(NetworkInterfaces.arpTable().count, table.count)
    }

    func testAnUnknownGatewayHasNoUpstream() {
        expectNil(NetworkInterfaces.upstreamMAC(gateway: "0.0.0.0", device: "nope99"))
        expectNil(NetworkInterfaces.upstreamMAC(gateway: "127.0.0.1", device: "lo0"))
        expectNil(NetworkInterfaces.upstreamMAC(gateway: "", device: ""))
    }

    func testTheUpstreamLookupIsScopedToItsInterface() {
        let table = NetworkInterfaces.arpTable()
        guard let entry = table.first else { return skip("the ARP table is empty on this machine") }
        expectNil(
            NetworkInterfaces.upstreamMAC(gateway: entry.ip, device: "lo0"),
            "an address learned on another interface must not be reported")
    }

    func testAKnownEntryResolvesOnItsOwnInterface() {
        let table = NetworkInterfaces.arpTable()
        guard let entry = table.first else { return skip("the ARP table is empty on this machine") }
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard let device = if_indextoname(entry.index, &name).map({ String(cString: $0) }) else {
            return fail("interface \(entry.index) should have a name")
        }
        expectEqual(NetworkInterfaces.upstreamMAC(gateway: entry.ip, device: device), entry.mac)
    }
}
