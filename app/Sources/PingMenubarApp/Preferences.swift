import Foundation

enum Preferences {
    static let hostKey = "host"
    static let intervalKey = "interval"
    static let timeoutKey = "timeout"
    static let warnKey = "warnThreshold"
    static let tcpPortKey = "tcpPort"
    static let showDotKey = "showDot"
    static let networkOnlyKey = "networkOnly"
    static let wifiExpandedKey = "wifiExpanded"
    static let wiredExpandedKey = "wiredExpanded"

    static let defaultHost = "1.1.1.1"
    static let defaultInterval: Double = 2
    static let defaultTimeout: Double = 2
    static let defaultWarn: Double = 0.12
    static let defaultPort = 443

    static let intervalRange: ClosedRange<Double> = 0.5...60
    static let timeoutRange: ClosedRange<Double> = 0.5...10
    static let warnRange: ClosedRange<Double> = 0.005...2

    nonisolated(unsafe) static var store: UserDefaults = .standard

    static var host: String {
        get {
            let stored = store.string(forKey: hostKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return stored.isEmpty ? defaultHost : stored
        }
        set { store.set(newValue, forKey: hostKey) }
    }

    static var interval: Double {
        get { clamp(store.object(forKey: intervalKey) as? Double ?? defaultInterval, to: intervalRange) }
        set { store.set(clamp(newValue, to: intervalRange), forKey: intervalKey) }
    }

    static var timeout: Double {
        get { clamp(store.object(forKey: timeoutKey) as? Double ?? defaultTimeout, to: timeoutRange) }
        set { store.set(clamp(newValue, to: timeoutRange), forKey: timeoutKey) }
    }

    static var warnThreshold: Double {
        get { clamp(store.object(forKey: warnKey) as? Double ?? defaultWarn, to: warnRange) }
        set { store.set(clamp(newValue, to: warnRange), forKey: warnKey) }
    }

    static var tcpPort: Int {
        get {
            let stored = store.object(forKey: tcpPortKey) as? Int ?? defaultPort
            return (1...65535).contains(stored) ? stored : defaultPort
        }
        set { store.set(newValue, forKey: tcpPortKey) }
    }

    static var showDot: Bool {
        get { store.object(forKey: showDotKey) as? Bool ?? true }
        set { store.set(newValue, forKey: showDotKey) }
    }

    static var networkOnly: Bool {
        get { store.object(forKey: networkOnlyKey) as? Bool ?? false }
        set { store.set(newValue, forKey: networkOnlyKey) }
    }

    static var wifiExpanded: Bool {
        get { store.object(forKey: wifiExpandedKey) as? Bool ?? false }
        set { store.set(newValue, forKey: wifiExpandedKey) }
    }

    static var wiredExpanded: Bool {
        get { store.object(forKey: wiredExpandedKey) as? Bool ?? false }
        set { store.set(newValue, forKey: wiredExpandedKey) }
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
