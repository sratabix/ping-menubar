import Foundation
import TestKit

@testable import PingMenubarApp

final class WiFiLogChangeTests: TestCase {
    private func snapshot(
        powered: Bool = true,
        rssi: Int? = -59,
        channel: Int? = 53,
        band: String? = "6 GHz",
        width: String? = "160 MHz",
        standard: String? = "Wi-Fi 6E (802.11ax)",
        security: String? = "WPA3 Personal",
        ipv4: String? = "198.51.100.10",
        gateway: String? = "198.51.100.1",
        upstream: String? = "00:00:5e:00:53:01"
    ) -> WiFiSnapshot {
        var snapshot = WiFiSnapshot()
        snapshot.powered = powered
        snapshot.rssi = rssi
        snapshot.noise = -91
        snapshot.channel = channel
        snapshot.band = band
        snapshot.width = width
        snapshot.standard = standard
        snapshot.security = security
        snapshot.ipv4 = ipv4
        snapshot.gateway = gateway
        snapshot.upstream = upstream
        return snapshot
    }

    func testTheFirstSnapshotLogsNothing() {
        expectEqual(WiFiLog.changes(from: nil, to: snapshot()), [])
    }

    func testAnUnchangedSnapshotLogsNothing() {
        expectEqual(WiFiLog.changes(from: snapshot(), to: snapshot()), [])
    }

    func testDriftingSignalWithinABandIsNotLogged() {
        expectEqual(WiFiLog.changes(from: snapshot(rssi: -58), to: snapshot(rssi: -62)), [])
    }

    func testCrossingASignalBandShowsBothSides() {
        expectEqual(
            WiFiLog.changes(from: snapshot(rssi: -50), to: snapshot(rssi: -70)),
            ["signal excellent → fair"])
    }

    func testTurningTheRadioOffShowsBothSides() {
        expectEqual(WiFiLog.changes(from: snapshot(), to: snapshot(powered: false)), ["Wi-Fi on → off"])
    }

    func testTurningTheRadioOnShowsBothSides() {
        expectEqual(WiFiLog.changes(from: snapshot(powered: false), to: snapshot()), ["Wi-Fi off → on"])
    }

    func testAPoweredOffRadioLogsNothingElse() {
        let off = snapshot(powered: false, ipv4: nil, gateway: nil, upstream: nil)
        expectEqual(WiFiLog.changes(from: off, to: snapshot(powered: false, ipv4: "203.0.113.1")), [])
    }

    func testAChannelChangeShowsBothSides() {
        expectEqual(WiFiLog.changes(from: snapshot(), to: snapshot(channel: 37)), ["channel 53 → 37"])
    }

    func testABandSteerLogsEachFieldSeparately() {
        let steered = snapshot(channel: 6, band: "2.4 GHz", width: "20 MHz")
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: steered),
            ["channel 53 → 6", "band 6 GHz → 2.4 GHz", "width 160 MHz → 20 MHz"])
    }

    func testAStandardChangeShowsBothSides() {
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: snapshot(standard: "Wi-Fi 5 (802.11ac)")),
            ["standard Wi-Fi 6E (802.11ax) → Wi-Fi 5 (802.11ac)"])
    }

    func testASecurityChangeShowsBothSides() {
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: snapshot(security: "open")),
            ["security WPA3 Personal → open"])
    }

    func testAnAddressChangeShowsBothSides() {
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: snapshot(ipv4: "203.0.113.5")),
            ["IP 198.51.100.10 → 203.0.113.5"])
    }

    func testLosingTheAddressShowsAnAbsentSide() {
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: snapshot(ipv4: nil)),
            ["IP 198.51.100.10 → —"])
    }

    func testGainingAnAddressShowsAnAbsentSide() {
        expectEqual(
            WiFiLog.changes(from: snapshot(ipv4: nil), to: snapshot()),
            ["IP — → 198.51.100.10"])
    }

    func testAGatewayChangeShowsBothSides() {
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: snapshot(gateway: "203.0.113.1")),
            ["gateway 198.51.100.1 → 203.0.113.1"])
    }

    func testAnUpstreamChangeShowsBothSides() {
        expectEqual(
            WiFiLog.changes(from: snapshot(), to: snapshot(upstream: "00:00:5e:00:53:ff")),
            ["upstream 00:00:5e:00:53:01 → 00:00:5e:00:53:ff"])
    }

    func testSeveralChangesAtOnceAreAllLogged() {
        let moved = snapshot(rssi: -80, channel: 6, band: "2.4 GHz", width: "20 MHz", ipv4: "203.0.113.5")
        let changes = WiFiLog.changes(from: snapshot(), to: moved)
        expectEqual(changes.count, 5)
        expectTrue(changes.contains("signal good → weak"))
        expectTrue(changes.contains("channel 53 → 6"))
        expectTrue(changes.contains("IP 198.51.100.10 → 203.0.113.5"))
    }

    func testEveryChangeCarriesAnArrow() {
        let moved = snapshot(rssi: -80, channel: 6, band: "2.4 GHz", ipv4: "203.0.113.5", upstream: nil)
        for change in WiFiLog.changes(from: snapshot(), to: moved) {
            expectTrue(change.contains(" → "), "\(change) should show what it changed to")
        }
    }

    func testTheChangeHelperIgnoresEqualSides() {
        expectNil(WiFiLog.change("channel", "1", "1"))
        expectNil(WiFiLog.change("channel", nil, nil))
        expectEqual(WiFiLog.change("channel", nil, "6"), "channel — → 6")
    }
}

final class WiFiLogAppendTests: TestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testAppendingNothingLeavesTheLogAlone() {
        let log = WiFiLog.append(["one"], to: [], at: now, nextID: 0)
        expectEqual(WiFiLog.append([], to: log, at: now, nextID: 1), log)
    }

    func testTheNewestEntryIsFirst() {
        var log = WiFiLog.append(["first"], to: [], at: now, nextID: 0)
        log = WiFiLog.append(["second"], to: log, at: now, nextID: 1)
        expectEqual(log.map(\.text), ["second", "first"])
    }

    func testEntriesFromOneSampleKeepTheirOrder() {
        let log = WiFiLog.append(["a", "b", "c"], to: [], at: now, nextID: 0)
        expectEqual(log.map(\.text), ["c", "b", "a"])
    }

    func testIdentifiersAreUnique() {
        var log = WiFiLog.append(["a", "b"], to: [], at: now, nextID: 0)
        log = WiFiLog.append(["c"], to: log, at: now, nextID: 2)
        expectEqual(log.map(\.id).count, Set(log.map(\.id)).count)
    }

    func testTheLogIsCappedAtTwenty() {
        var log: [LogEntry] = []
        for index in 0..<40 {
            log = WiFiLog.append(["entry \(index)"], to: log, at: now, nextID: index)
        }
        expectEqual(log.count, WiFiLog.capacity)
        expectEqual(log.count, 20)
    }

    func testTheCapDropsTheOldestEntries() {
        var log: [LogEntry] = []
        for index in 0..<25 {
            log = WiFiLog.append(["entry \(index)"], to: log, at: now, nextID: index)
        }
        expectEqual(log.first?.text, "entry 24")
        expectEqual(log.last?.text, "entry 5")
    }

    func testABurstLargerThanTheCapIsTrimmed() {
        let burst = (0..<30).map { "entry \($0)" }
        let log = WiFiLog.append(burst, to: [], at: now, nextID: 0)
        expectEqual(log.count, WiFiLog.capacity)
    }

    func testALineCombinesTheTimeAndTheChange() {
        let entry = LogEntry(id: 0, at: now, text: "channel 53 → 6")
        let line = WiFiLog.line(entry)
        expectTrue(line.hasSuffix("  channel 53 → 6"))
        expectTrue(line.contains(WiFiLog.time.string(from: now)))
    }

    func testEntriesCarryTheirTimestamp() {
        let log = WiFiLog.append(["one"], to: [], at: now, nextID: 0)
        expectEqual(log.first?.at, now)
    }

    func testTimesAreFormattedAsAClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = WiFiLog.time.dateFormat
        formatter.timeZone = TimeZone(identifier: "UTC")
        expectEqual(formatter.string(from: now), "22:13:20")
    }
}

final class SelectableLogTests: TestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let width: CGFloat = 256

    private func log(_ count: Int, text: String = "channel 53 → 6") -> [LogEntry] {
        (0..<count).map { LogEntry(id: $0, at: now, text: text) }
    }

    private func height(_ entries: [LogEntry]) -> CGFloat {
        SelectableLog.height(of: SelectableLog(entries: entries).attributed, width: width)
    }

    func testAnEmptyLogHasOnlyItsInset() {
        expectEqual(height([]), SelectableLog.inset.height * 2)
    }

    func testHeightGrowsWithEntries() {
        expectGreaterThan(height(log(3)), height(log(1)))
    }

    func testHeightIsCapped() {
        expectAtMost(height(log(WiFiLog.capacity)), SelectableLog.maxHeight)
    }

    func testAFullLogReachesTheCap() {
        expectEqual(height(log(WiFiLog.capacity)), SelectableLog.maxHeight)
    }

    func testWrappingEntriesStillCannotGrowThePanel() {
        let long = "upstream 00:00:5e:00:53:02 → 00:00:5e:00:53:01 and then some more text to force wrapping"
        expectAtMost(height(log(WiFiLog.capacity, text: long)), SelectableLog.maxHeight)
    }

    func testASingleEntryIsShorterThanTheCap() {
        expectLessThan(height(log(1)), SelectableLog.maxHeight)
    }

    func testTheAttributedLogCarriesEveryEntry() {
        let text = SelectableLog(entries: log(3)).attributed.string
        expectEqual(text.components(separatedBy: "\n").count, 3)
        expectTrue(text.contains("channel 53 → 6"))
    }

    func testTheTimeIsPartOfTheSelectableText() {
        let text = SelectableLog(entries: log(1)).attributed.string
        expectTrue(text.hasPrefix(WiFiLog.time.string(from: now)))
    }

    func testWrappedLinesHangUnderTheTextColumn() {
        expectGreaterThan(SelectableLog(entries: log(1)).indent, 0)
    }
}
