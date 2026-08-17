import Foundation
import IOKit
import SystemConfiguration

struct WiredSnapshot: Equatable {
    var device: String
    var adapter: String?
    var linkUp = false
    var speed: String?
    var duplex: String?
    var ipv4: String?
    var gateway: String?
    var upstream: String?
    var throughput: Throughput?
}

@MainActor
final class WiredMonitor {
    private struct Counters {
        var at: TimeInterval
        var input: UInt64
        var output: UInt64
    }

    private var previous: [String: Counters] = [:]

    func snapshots() -> [WiredSnapshot] {
        let global = NetworkInterfaces.globalIPv4()
        var found: [WiredSnapshot] = []

        for port in NetworkInterfaces.ethernetPorts() {
            let media = Media.of(port.device) ?? Media.Report(linkUp: false, speed: nil, duplex: nil)
            guard media.linkUp || Hardware.isExternal(port.device) else { continue }
            let gateway = media.linkUp ? NetworkInterfaces.router(of: port.device) : nil
            found.append(
                WiredSnapshot(
                    device: port.device,
                    adapter: port.name,
                    linkUp: media.linkUp,
                    speed: media.speed,
                    duplex: media.duplex,
                    ipv4: media.linkUp ? NetworkInterfaces.address(of: port.device) : nil,
                    gateway: gateway,
                    upstream: gateway.flatMap {
                        NetworkInterfaces.upstreamMAC(gateway: $0, device: port.device)
                    },
                    throughput: media.linkUp ? throughput(of: port.device) : nil
                ))
        }

        previous = previous.filter { device, _ in found.contains { $0.device == device } }
        return found.sorted { first, second in
            if first.linkUp != second.linkUp { return first.linkUp }
            if (first.device == global.primaryInterface) != (second.device == global.primaryInterface) {
                return first.device == global.primaryInterface
            }
            return first.device < second.device
        }
    }

    func reset() {
        previous.removeAll()
    }

    private func throughput(of device: String) -> Throughput? {
        guard let counters = NetworkInterfaces.counters(of: device) else { return nil }
        let now = Clock.now()
        guard let last = previous[device] else {
            previous[device] = Counters(at: now, input: counters.input, output: counters.output)
            return nil
        }

        let elapsed = now - last.at
        guard elapsed >= 0.2 else { return nil }
        previous[device] = Counters(at: now, input: counters.input, output: counters.output)
        guard counters.input >= last.input, counters.output >= last.output else { return nil }

        return Throughput(
            down: Double(counters.input - last.input) * 8 / elapsed,
            up: Double(counters.output - last.output) * 8 / elapsed
        )
    }
}

enum Media {
    static let avalid: Int32 = 0x0000_0001
    static let active: Int32 = 0x0000_0002
    static let subtypeMask: Int32 = 0x000f_001f
    static let fullDuplex: Int32 = 0x0010_0000
    static let halfDuplex: Int32 = 0x0020_0000

    struct Report: Equatable {
        var linkUp: Bool
        var speed: String?
        var duplex: String?
    }

    static func of(_ device: String) -> Report? {
        guard let words = words(of: device) else { return nil }
        return report(active: words.active, status: words.status)
    }

    static func report(active: Int32, status: Int32) -> Report {
        let linkUp = status & avalid != 0 && status & self.active != 0
        guard linkUp else { return Report(linkUp: false, speed: nil, duplex: nil) }
        return Report(linkUp: true, speed: speed(active), duplex: duplex(active))
    }

    static func speed(_ active: Int32) -> String? {
        switch active & subtypeMask {
        case 3, 12, 13: return "10 Mbps"
        case 6, 7, 8, 9, 10: return "100 Mbps"
        case 11, 14, 15, 16: return "1 Gbps"
        case 18, 19, 20, 21: return "10 Gbps"
        case 22: return "2.5 Gbps"
        case 23: return "5 Gbps"
        default: return nil
        }
    }

    static func duplex(_ active: Int32) -> String? {
        if active & fullDuplex != 0 { return "full duplex" }
        if active & halfDuplex != 0 { return "half duplex" }
        return nil
    }

    private static let request: UInt = {
        let size = UInt(MemoryLayout<ifmediareq>.size & 0x1fff) << 16
        return 0xC000_0000 | size | (UInt(UInt8(ascii: "i")) << 8) | 56
    }()

    private static func words(of device: String) -> (active: Int32, status: Int32)? {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var query = ifmediareq()
        withUnsafeMutableBytes(of: &query.ifm_name) { raw in
            device.utf8CString.withUnsafeBytes { source in
                guard let base = source.baseAddress else { return }
                raw.copyMemory(from: UnsafeRawBufferPointer(start: base, count: min(source.count, 16)))
            }
        }
        guard ioctl(descriptor, request, &query) == 0 else { return nil }
        return (query.ifm_active, query.ifm_status)
    }
}

extension NetworkInterfaces {
    struct Port: Equatable {
        var device: String
        var name: String?
    }

    static func ethernetPorts() -> [Port] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        return all.compactMap { interface in
            guard
                SCNetworkInterfaceGetInterfaceType(interface) as String? == (kSCNetworkInterfaceTypeEthernet as String),
                let device = SCNetworkInterfaceGetBSDName(interface) as String?
            else { return nil }
            return Port(device: device, name: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?)
        }
    }
}

enum Hardware {
    static let builtInProviders = ["IOUSBDeviceInterface", "IOThunderboltLocalNode"]

    static func isExternal(_ device: String) -> Bool {
        let chain = ancestry(of: device)
        guard !chain.isEmpty else { return false }
        return !chain.contains { builtInProviders.contains($0) }
    }

    static func ancestry(of device: String) -> [String] {
        guard let matching = IOServiceMatching("IOEthernetInterface") else { return [] }
        let query = matching as NSMutableDictionary
        query[kIOPropertyMatchKey] = ["BSD Name": device] as NSDictionary

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, query, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return [] }

        var chain: [String] = []
        var current = service
        while chain.count < 12 {
            var name = [CChar](repeating: 0, count: 128)
            if IOObjectGetClass(current, &name) == KERN_SUCCESS {
                chain.append(String(cString: name))
            }
            var parent: io_registry_entry_t = 0
            let found = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS
            IOObjectRelease(current)
            guard found, parent != 0 else { break }
            current = parent
        }
        return chain
    }
}
