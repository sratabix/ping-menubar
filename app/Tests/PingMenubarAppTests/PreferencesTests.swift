import Foundation
import TestKit

@testable import PingMenubarApp

final class PreferencesTests: TestCase {
    private let suite = "nl.pingmenubar.tests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        Preferences.store = UserDefaults(suiteName: suite) ?? .standard
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        Preferences.store = .standard
        super.tearDown()
    }

    func testDefaults() {
        expectEqual(Preferences.host, "1.1.1.1")
        expectEqual(Preferences.interval, 2)
        expectEqual(Preferences.timeout, 2)
        expectEqual(Preferences.warnThreshold, 0.12)
        expectEqual(Preferences.tcpPort, 443)
        expectTrue(Preferences.showDot)
        expectFalse(Preferences.networkOnly)
        expectFalse(Preferences.wifiExpanded)
        expectFalse(Preferences.wiredExpanded)
    }

    func testValuesPersist() {
        Preferences.host = "example.com"
        Preferences.interval = 5
        Preferences.timeout = 3
        Preferences.warnThreshold = 0.2
        Preferences.tcpPort = 80
        Preferences.showDot = false
        Preferences.networkOnly = true
        Preferences.wifiExpanded = true
        Preferences.wiredExpanded = true

        expectEqual(Preferences.host, "example.com")
        expectEqual(Preferences.interval, 5)
        expectEqual(Preferences.timeout, 3)
        expectEqual(Preferences.warnThreshold, 0.2)
        expectEqual(Preferences.tcpPort, 80)
        expectFalse(Preferences.showDot)
        expectTrue(Preferences.networkOnly)
        expectTrue(Preferences.wifiExpanded)
        expectTrue(Preferences.wiredExpanded)
    }

    func testAnEmptyHostFallsBackToTheDefault() {
        Preferences.host = "   "
        expectEqual(Preferences.host, "1.1.1.1")
    }

    func testAStoredHostIsTrimmed() {
        Preferences.host = "  example.com  "
        expectEqual(Preferences.host, "example.com")
    }

    func testIntervalIsClampedOnWrite() {
        Preferences.interval = 0.1
        expectEqual(Preferences.interval, Preferences.intervalRange.lowerBound)
        Preferences.interval = 9999
        expectEqual(Preferences.interval, Preferences.intervalRange.upperBound)
    }

    func testTimeoutIsClampedOnWrite() {
        Preferences.timeout = 0
        expectEqual(Preferences.timeout, Preferences.timeoutRange.lowerBound)
        Preferences.timeout = 100
        expectEqual(Preferences.timeout, Preferences.timeoutRange.upperBound)
    }

    func testWarnThresholdIsClampedOnWrite() {
        Preferences.warnThreshold = 0
        expectEqual(Preferences.warnThreshold, Preferences.warnRange.lowerBound)
        Preferences.warnThreshold = 60
        expectEqual(Preferences.warnThreshold, Preferences.warnRange.upperBound)
    }

    func testAValueStoredOutOfRangeIsClampedOnRead() {
        Preferences.store.set(9999.0, forKey: Preferences.intervalKey)
        expectEqual(Preferences.interval, Preferences.intervalRange.upperBound)
    }

    func testAnImpossiblePortFallsBackToTheDefault() {
        Preferences.store.set(0, forKey: Preferences.tcpPortKey)
        expectEqual(Preferences.tcpPort, 443)
        Preferences.store.set(70000, forKey: Preferences.tcpPortKey)
        expectEqual(Preferences.tcpPort, 443)
    }

    func testAPortAtTheEdgesIsKept() {
        Preferences.tcpPort = 1
        expectEqual(Preferences.tcpPort, 1)
        Preferences.tcpPort = 65535
        expectEqual(Preferences.tcpPort, 65535)
    }

    func testClampLeavesValuesInsideTheRangeAlone() {
        expectEqual(Preferences.clamp(3, to: 1...10), 3)
        expectEqual(Preferences.clamp(0, to: 1...10), 1)
        expectEqual(Preferences.clamp(11, to: 1...10), 10)
    }
}
