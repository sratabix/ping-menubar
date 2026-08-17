import CoreWLAN
import Foundation
import TestKit

@testable import PingMenubarApp

final class MediaTests: TestCase {
    func testLinkIsDownWithoutTheActiveBit() {
        expectFalse(Media.report(active: 0x0000_0022, status: 0x1).linkUp)
        expectFalse(Media.report(active: 0x0010_0020, status: 0x1).linkUp)
    }

    func testLinkIsDownWhenTheStatusIsNotValid() {
        expectFalse(Media.report(active: 0x0010_0016, status: 0x0).linkUp)
        expectFalse(Media.report(active: 0x0010_0016, status: 0x2).linkUp)
    }

    func testADownLinkReportsNoSpeedOrDuplex() {
        let report = Media.report(active: 0x0010_0016, status: 0x1)
        expectNil(report.speed)
        expectNil(report.duplex)
    }

    func testAConnectedAdapterReportsSpeedAndDuplex() {
        let report = Media.report(active: 0x0010_0016, status: 0x3)
        expectTrue(report.linkUp)
        expectEqual(report.speed, "2.5 Gbps")
        expectEqual(report.duplex, "full duplex")
    }

    func testSpeedsAreDecodedFromTheSubtype() {
        expectEqual(Media.speed(0x0000_0003), "10 Mbps")
        expectEqual(Media.speed(0x0010_0006), "100 Mbps")
        expectEqual(Media.speed(0x0010_0007), "100 Mbps")
        expectEqual(Media.speed(0x0010_000B), "1 Gbps")
        expectEqual(Media.speed(0x0010_0010), "1 Gbps")
        expectEqual(Media.speed(0x0010_0012), "10 Gbps")
        expectEqual(Media.speed(0x0010_0015), "10 Gbps")
        expectEqual(Media.speed(0x0010_0016), "2.5 Gbps")
        expectEqual(Media.speed(0x0010_0017), "5 Gbps")
    }

    func testDuplexBitsDoNotDisturbTheSpeed() {
        expectEqual(Media.speed(0x0000_0010), "1 Gbps")
        expectEqual(Media.speed(0x0010_0010), "1 Gbps")
        expectEqual(Media.speed(0x0020_0010), "1 Gbps")
    }

    func testAutoselectAndNoneHaveNoSpeed() {
        expectNil(Media.speed(0x0010_0020))
        expectNil(Media.speed(0x0000_0022))
        expectNil(Media.speed(0x0000_0000))
    }

    func testDuplexIsReadFromTheOptionBits() {
        expectEqual(Media.duplex(0x0010_0016), "full duplex")
        expectEqual(Media.duplex(0x0020_0006), "half duplex")
        expectNil(Media.duplex(0x0000_0003))
    }

    func testQueryingAnUnknownDeviceReturnsNothing() {
        expectNil(Media.of("nope99"))
    }

    func testADeviceWithoutMediaReturnsNothing() {
        expectNil(Media.of("lo0"), "loopback does not answer SIOCGIFMEDIA")
    }

    func testEveryEthernetPortAnswersTheMediaQuery() {
        let ports = NetworkInterfaces.ethernetPorts()
        guard !ports.isEmpty else { return skip("no Ethernet ports on this machine") }
        for port in ports {
            expectNotNil(Media.of(port.device), "\(port.device) should report its media state")
        }
    }
}

final class HardwareTests: TestCase {
    private var ports: [String] { NetworkInterfaces.ethernetPorts().map(\.device) }

    func testTheMacsOwnUSBDeviceEndpointsAreNotAdapters() {
        for builtIn in ["en4", "en5", "en8"] where ports.contains(builtIn) {
            expectFalse(
                Hardware.isExternal(builtIn),
                "\(builtIn) is the Mac acting as a USB device, not an attached adapter")
        }
    }

    func testThunderboltBridgePortsAreNotAdapters() {
        for bridge in ["en1", "en2", "en3"] where ports.contains(bridge) {
            expectFalse(Hardware.isExternal(bridge), "\(bridge) is a built-in Thunderbolt bridge port")
        }
    }

    func testAnUnknownDeviceIsNotExternal() {
        expectFalse(Hardware.isExternal("nope99"))
        expectTrue(Hardware.ancestry(of: "nope99").isEmpty)
    }

    func testAncestryStartsAtTheInterfaceItself() {
        guard let device = ports.first(where: { !Hardware.ancestry(of: $0).isEmpty }) else {
            return fail("the Mac should expose at least one Ethernet port")
        }
        expectEqual(Hardware.ancestry(of: device).first, "IOEthernetInterface")
    }

    func testAncestryIsBounded() {
        for device in ports {
            expectAtMost(Hardware.ancestry(of: device).count, 12)
        }
    }

    func testAnAttachedAdapterExposesItsProviderChain() {
        let external = ports.filter { Hardware.isExternal($0) }
        guard !external.isEmpty else { return skip("no external Ethernet adapter attached") }
        for device in external {
            expectFalse(Hardware.ancestry(of: device).isEmpty)
        }
    }
}

final class EthernetPortTests: TestCase {
    private var devices: Set<String> { Set(NetworkInterfaces.ethernetPorts().map(\.device)) }

    func testVirtualInterfacesAreNotEthernetPorts() {
        for virtual in ["vmenet0", "vmenet1", "bridge100", "awdl0", "lo0", "utun6", "gif0", "stf0"] {
            expectFalse(devices.contains(virtual), "\(virtual) must never be offered as a LAN port")
        }
    }

    func testTheWiFiInterfaceIsNotAnEthernetPort() {
        guard let radio = CWWiFiClient.shared().interface()?.interfaceName else {
            return skip("no Wi-Fi interface on this machine")
        }
        expectFalse(devices.contains(radio), "\(radio) is the Wi-Fi radio, not a LAN port")
    }

    func testEveryPortHasABSDName() {
        for port in NetworkInterfaces.ethernetPorts() {
            expectFalse(port.device.isEmpty)
        }
    }

    func testPortsAreUnique() {
        let listed = NetworkInterfaces.ethernetPorts().map(\.device)
        expectEqual(listed.count, Set(listed).count)
    }
}
