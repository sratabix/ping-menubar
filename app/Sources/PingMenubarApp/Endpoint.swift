import Foundation

enum ProbeMode: String, Equatable {
    case icmp
    case tcp
}

enum ProbeFailure: Error, Equatable {
    case dns(String)
    case unreachable(String)
    case socket(String)
    case timeout
}

struct Endpoint: Equatable {
    var family: Int32
    var address: sockaddr_storage
    var length: socklen_t
    var text: String

    static func == (lhs: Endpoint, rhs: Endpoint) -> Bool {
        lhs.family == rhs.family && lhs.text == rhs.text
    }

    var isIPv6: Bool { family == AF_INET6 }

    func withPort(_ port: UInt16) -> Endpoint {
        var copy = self
        withUnsafeMutableBytes(of: &copy.address) { raw in
            let offset =
                family == AF_INET6
                ? MemoryLayout<sockaddr_in6>.offset(of: \.sin6_port) : MemoryLayout<sockaddr_in>.offset(of: \.sin_port)
            guard let offset else { return }
            raw.storeBytes(of: port.bigEndian, toByteOffset: offset, as: UInt16.self)
        }
        return copy
    }

    func withSocketAddress<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var storage = address
        return withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
        }
    }
}

enum Resolver {
    static func resolve(_ host: String) -> Result<Endpoint, ProbeFailure> {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.dns("no host configured")) }

        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var head: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(trimmed, nil, &hints, &head)
        guard status == 0, let head else {
            return .failure(.dns(String(cString: gai_strerror(status))))
        }
        defer { freeaddrinfo(head) }

        var chosen: addrinfo?
        var candidate = Optional(head.pointee)
        while let current = candidate {
            if current.ai_family == AF_INET {
                chosen = current
                break
            }
            if chosen == nil, current.ai_family == AF_INET6 { chosen = current }
            candidate = current.ai_next?.pointee
        }
        guard let chosen, let addr = chosen.ai_addr else {
            return .failure(.dns("no usable address"))
        }

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { raw in
            raw.copyMemory(from: UnsafeRawBufferPointer(start: addr, count: Int(chosen.ai_addrlen)))
        }
        return .success(
            Endpoint(
                family: chosen.ai_family,
                address: storage,
                length: chosen.ai_addrlen,
                text: numericHost(addr, length: chosen.ai_addrlen) ?? trimmed
            ))
    }

    private static func numericHost(_ addr: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(addr, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
        guard status == 0 else { return nil }
        return String(cString: buffer)
    }
}
