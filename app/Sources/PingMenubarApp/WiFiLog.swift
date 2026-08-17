import Foundation

struct LogEntry: Equatable, Identifiable {
    var id: Int
    var at: Date
    var text: String
}

enum WiFiLog {
    static let capacity = 20
    static let absent = "—"

    static func changes(from previous: WiFiSnapshot?, to current: WiFiSnapshot) -> [String] {
        guard let previous else { return [] }
        guard previous.powered == current.powered else {
            return [change("Wi-Fi", previous.powered ? "on" : "off", current.powered ? "on" : "off")].compactMap { $0 }
        }
        guard current.powered else { return [] }

        return [
            change("signal", previous.qualityLabel, current.qualityLabel),
            change("channel", previous.channel.map(String.init), current.channel.map(String.init)),
            change("band", previous.band, current.band),
            change("width", previous.width, current.width),
            change("standard", previous.standard, current.standard),
            change("security", previous.security, current.security),
            change("IP", previous.ipv4, current.ipv4),
            change("gateway", previous.gateway, current.gateway),
            change("upstream", previous.upstream, current.upstream),
        ].compactMap { $0 }
    }

    static func change(_ label: String, _ old: String?, _ new: String?) -> String? {
        guard old != new else { return nil }
        return "\(label) \(old ?? absent) → \(new ?? absent)"
    }

    static func append(_ texts: [String], to log: [LogEntry], at now: Date, nextID: Int) -> [LogEntry] {
        guard !texts.isEmpty else { return log }
        var updated = log
        for (offset, text) in texts.enumerated() {
            updated.insert(LogEntry(id: nextID + offset, at: now, text: text), at: 0)
        }
        if updated.count > capacity { updated.removeLast(updated.count - capacity) }
        return updated
    }

    static func line(_ entry: LogEntry) -> String {
        "\(time.string(from: entry.at))  \(entry.text)"
    }

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
