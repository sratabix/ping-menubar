import Foundation

enum PingState: Equatable {
    case waiting
    case ok(TimeInterval)
    case slow(TimeInterval)
    case dns
    case offline

    var latency: TimeInterval? {
        switch self {
        case .ok(let rtt), .slow(let rtt): return rtt
        case .waiting, .dns, .offline: return nil
        }
    }
}

struct StatusPolicy {
    var warn: TimeInterval
    var failuresBeforeOffline: Int

    func state(
        latest: TimeInterval?,
        failureStreak: Int,
        dnsFailing: Bool,
        pathSatisfied: Bool
    ) -> PingState {
        guard pathSatisfied else { return .offline }
        if failureStreak >= failuresBeforeOffline { return .offline }
        guard let latest else { return dnsFailing ? .dns : .waiting }
        if dnsFailing { return .dns }
        return latest >= warn ? .slow(latest) : .ok(latest)
    }
}

struct Sample: Equatable {
    var at: TimeInterval
    var value: Double?

    var lost: Bool { value == nil }
}

struct Samples: Equatable {
    static let defaultWindow: TimeInterval = 60
    private static let hardCap = 1200

    private(set) var values: [Sample] = []
    let window: TimeInterval

    init(window: TimeInterval = Samples.defaultWindow) {
        self.window = window
    }

    mutating func append(_ value: Double?, at: TimeInterval = Clock.now()) {
        values.append(Sample(at: at, value: value))
        trim(now: at)
    }

    mutating func clear() {
        values.removeAll()
    }

    private mutating func trim(now: TimeInterval) {
        let cutoff = now - window
        if let keep = values.firstIndex(where: { $0.at > cutoff }), keep > 0 {
            values.removeFirst(keep)
        }
        if values.count > Self.hardCap { values.removeFirst(values.count - Self.hardCap) }
    }

    var end: TimeInterval? { values.last?.at }
    var start: TimeInterval? { end.map { $0 - window } }

    private var received: [Double] { values.compactMap(\.value) }

    var latest: Double? { values.last?.value }
    var lastReceived: Double? { values.last(where: { !$0.lost })?.value }
    var average: Double? {
        let received = received
        guard !received.isEmpty else { return nil }
        return received.reduce(0, +) / Double(received.count)
    }
    var minimum: Double? { received.min() }
    var maximum: Double? { received.max() }
    var total: Int { values.count }
    var lost: Int { values.count - received.count }
    var loss: Double {
        guard !values.isEmpty else { return 0 }
        return Double(lost) / Double(values.count)
    }
}
