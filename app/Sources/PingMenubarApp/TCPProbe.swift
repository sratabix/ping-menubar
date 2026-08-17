import Foundation

enum TCPProbe {
    static func connect(_ endpoint: Endpoint, port: UInt16, timeout: TimeInterval) -> Result<TimeInterval, ProbeFailure>
    {
        let target = endpoint.withPort(port)
        let descriptor = socket(target.family, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else { return .failure(.socket(Errno.describe())) }
        defer { close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return .failure(.socket(Errno.describe()))
        }

        let started = Clock.now()
        let result = target.withSocketAddress { address, length in
            Darwin.connect(descriptor, address, length)
        }
        if result == 0 { return .success(Clock.now() - started) }
        if errno == ECONNREFUSED || errno == ECONNRESET { return .success(Clock.now() - started) }
        guard errno == EINPROGRESS else { return .failure(classify(errno)) }

        let deadline = started + timeout
        while true {
            let remaining = deadline - Clock.now()
            guard remaining > 0 else { return .failure(.timeout) }

            var descriptors = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptors, 1, Int32((remaining * 1000).rounded(.up)))
            if ready < 0 {
                guard errno == EINTR else { return .failure(.socket(Errno.describe())) }
                continue
            }
            guard ready > 0 else { return .failure(.timeout) }

            let elapsed = Clock.now() - started
            var pending: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &pending, &size) == 0 else {
                return .failure(.socket(Errno.describe()))
            }
            if pending == 0 || pending == ECONNREFUSED || pending == ECONNRESET {
                return .success(elapsed)
            }
            return .failure(classify(pending))
        }
    }

    private static func classify(_ code: Int32) -> ProbeFailure {
        switch code {
        case ETIMEDOUT: return .timeout
        case ENETDOWN, ENETUNREACH, EHOSTDOWN, EHOSTUNREACH: return .unreachable(Errno.describe(code))
        default: return .socket(Errno.describe(code))
        }
    }
}
