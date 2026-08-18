import CoreWLAN
import Foundation
import SystemConfiguration

struct Throughput: Equatable {
    var down: Double
    var up: Double
}

struct WiFiSnapshot: Equatable {
    var interfaceName: String?
    var powered = false

    var security: String?
    var standard: String?

    var rssi: Int?
    var noise: Int?
    var transmitRate: Double?

    var channel: Int?
    var band: String?
    var width: String?

    var ipv4: String?
    var gateway: String?
    var upstream: String?

    var throughput: Throughput?

    var snr: Int? {
        guard let rssi, let noise else { return nil }
        return rssi - noise
    }

    var quality: Double? {
        guard let rssi else { return nil }
        return SignalScale.quality(Double(rssi))
    }

    var qualityLabel: String? {
        guard let rssi else { return nil }
        switch rssi {
        case (-55)...: return "excellent"
        case (-67)..<(-55): return "good"
        case (-75)..<(-67): return "fair"
        default: return "weak"
        }
    }

}

@MainActor
final class WiFiMonitor {
    private let client = CWWiFiClient.shared()
    private var previous: (at: TimeInterval, input: UInt64, output: UInt64)?

    func snapshot() -> WiFiSnapshot {
        var snapshot = WiFiSnapshot()
        guard let interface = client.interface() else { return snapshot }

        let name = interface.interfaceName
        snapshot.interfaceName = name
        snapshot.powered = interface.powerOn()
        snapshot.security = WiFiNames.security(interface.security())

        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let rate = interface.transmitRate()
        snapshot.rssi = rssi == 0 ? nil : rssi
        snapshot.noise = noise == 0 ? nil : noise
        snapshot.transmitRate = rate == 0 ? nil : rate

        if let channel = interface.wlanChannel() {
            snapshot.channel = channel.channelNumber
            snapshot.band = WiFiNames.band(channel.channelBand)
            snapshot.width = WiFiNames.width(channel.channelWidth)
            snapshot.standard = WiFiNames.standard(interface.activePHYMode(), band: channel.channelBand)
        } else {
            snapshot.standard = WiFiNames.standard(interface.activePHYMode(), band: .bandUnknown)
        }

        guard let name else { return snapshot }
        snapshot.ipv4 = NetworkInterfaces.address(of: name)
        snapshot.gateway = NetworkInterfaces.router(of: name)
        snapshot.upstream = snapshot.gateway.flatMap {
            NetworkInterfaces.upstreamMAC(gateway: $0, device: name)
        }
        snapshot.throughput = throughput(of: name)
        return snapshot
    }

    func reset() {
        previous = nil
    }

    private func throughput(of name: String) -> Throughput? {
        guard let counters = NetworkInterfaces.counters(of: name) else { return nil }
        let now = Clock.now()
        guard let previous else {
            self.previous = (now, counters.input, counters.output)
            return nil
        }

        let elapsed = now - previous.at
        guard elapsed >= 0.2 else { return nil }
        self.previous = (now, counters.input, counters.output)
        guard counters.input >= previous.input, counters.output >= previous.output else { return nil }

        return Throughput(
            down: Double(counters.input - previous.input) * 8 / elapsed,
            up: Double(counters.output - previous.output) * 8 / elapsed
        )
    }
}

enum NetworkInterfaces {
    static func counters(of name: String) -> (input: UInt64, output: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = head
        while let current = pointer {
            let entry = current.pointee
            defer { pointer = entry.ifa_next }
            guard
                String(cString: entry.ifa_name) == name,
                entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                let data = entry.ifa_data
            else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            return (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
        }
        return nil
    }

    static func address(of name: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = head
        while let current = pointer {
            let entry = current.pointee
            defer { pointer = entry.ifa_next }
            guard
                String(cString: entry.ifa_name) == name,
                let addr = entry.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(addr.pointee.sa_len)
            guard
                getnameinfo(addr, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: buffer)
        }
        return nil
    }

    static func router(of device: String) -> String? {
        guard
            let store = SCDynamicStoreCreate(nil, "pingmenubar" as CFString, nil, nil),
            let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString)
                as? [String]
        else { return nil }

        for key in keys {
            guard
                let service = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                service["InterfaceName"] as? String == device
            else { continue }
            return service["Router"] as? String
        }
        return nil
    }

    struct ARPEntry: Equatable {
        var ip: String
        var mac: String
        var index: UInt32
    }

    static func upstreamMAC(gateway: String, device: String) -> String? {
        let index = if_nametoindex(device)
        return arpTable().first { entry in
            entry.ip == gateway && (index == 0 || entry.index == index)
        }?.mac
    }

    static func arpTable() -> [ARPEntry] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 6, &buffer, &size, nil, 0) == 0 else { return [] }

        var entries: [ARPEntry] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<rt_msghdr2>.size <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr2.self)
                let length = Int(header.rtm_msglen)
                guard length > 0, offset + length <= size else { return }
                defer { offset += length }

                let addressOffset = offset + MemoryLayout<rt_msghdr2>.size
                guard addressOffset + MemoryLayout<sockaddr_in>.size <= size else { continue }
                let address = raw.loadUnaligned(fromByteOffset: addressOffset, as: sockaddr_in.self)

                let stride =
                    Int(address.sin_len) == 0
                    ? MemoryLayout<sockaddr_in>.size
                    : (Int(address.sin_len) + 3) & ~3
                let linkOffset = addressOffset + stride
                guard linkOffset + MemoryLayout<sockaddr_dl>.size <= size else { continue }
                var link = raw.loadUnaligned(fromByteOffset: linkOffset, as: sockaddr_dl.self)
                guard link.sdl_alen == 6 else { continue }

                let name = Int(link.sdl_nlen)
                let mac = withUnsafeBytes(of: &link.sdl_data) { bytes in
                    (0..<6).map { String(format: "%02x", bytes[name + $0]) }.joined(separator: ":")
                }
                entries.append(
                    ARPEntry(ip: text(of: address.sin_addr), mac: mac, index: UInt32(link.sdl_index)))
            }
        }
        return entries
    }

    private static func text(of address: in_addr) -> String {
        let octets = withUnsafeBytes(of: address.s_addr) { Array($0) }
        return octets.map(String.init).joined(separator: ".")
    }

    static func globalIPv4() -> (router: String?, primaryInterface: String?) {
        guard
            let store = SCDynamicStoreCreate(nil, "pingmenubar" as CFString, nil, nil),
            let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any]
        else { return (nil, nil) }
        return (global["Router"] as? String, global["PrimaryInterface"] as? String)
    }
}

enum WiFiNames {
    static func security(_ security: CWSecurity) -> String? {
        switch security {
        case .none: return "open"
        case .WEP, .dynamicWEP: return "WEP"
        case .wpaPersonal, .wpaPersonalMixed: return "WPA Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed: return "WPA Enterprise"
        case .wpa2Personal: return "WPA2 Personal"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .wpa3Transition: return "WPA2/WPA3"
        case .personal: return "Personal"
        case .enterprise: return "Enterprise"
        case .OWE, .oweTransition: return "Enhanced Open"
        case .unknown: return nil
        @unknown default: return nil
        }
    }

    static func band(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        case .bandUnknown: return nil
        @unknown default: return nil
        }
    }

    static func width(_ width: CWChannelWidth) -> String? {
        switch width {
        case .width20MHz: return "20 MHz"
        case .width40MHz: return "40 MHz"
        case .width80MHz: return "80 MHz"
        case .width160MHz: return "160 MHz"
        case .widthUnknown: return nil
        @unknown default: return nil
        }
    }

    static func standard(_ mode: CWPHYMode, band: CWChannelBand) -> String? {
        switch mode.rawValue {
        case 1: return "802.11a"
        case 2: return "802.11b"
        case 3: return "802.11g"
        case 4: return "Wi-Fi 4 (802.11n)"
        case 5: return "Wi-Fi 5 (802.11ac)"
        case 6: return band == .band6GHz ? "Wi-Fi 6E (802.11ax)" : "Wi-Fi 6 (802.11ax)"
        case 7: return "Wi-Fi 7 (802.11be)"
        default: return nil
        }
    }

    static func rate(_ megabitsPerSecond: Double) -> String {
        megabitsPerSecond >= 1000
            ? String(format: "%.2f Gbps", megabitsPerSecond / 1000)
            : "\(Int(megabitsPerSecond.rounded())) Mbps"
    }

    static func throughput(_ bitsPerSecond: Double) -> String {
        switch bitsPerSecond {
        case ..<1_000: return "0 Kbps"
        case ..<1_000_000: return "\(Int((bitsPerSecond / 1_000).rounded())) Kbps"
        case ..<1_000_000_000: return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        default: return String(format: "%.2f Gbps", bitsPerSecond / 1_000_000_000)
        }
    }
}
