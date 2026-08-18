import Foundation
import TestKit

@testable import PingMenubarApp

final class StatusPolicyTests: TestCase {
    private let policy = StatusPolicy(warn: 0.120, failuresBeforeOffline: 2)

    func testFastReplyIsOk() {
        expectEqual(state(latest: 0.014), .ok(0.014))
    }

    func testReplyBelowTheThresholdIsOk() {
        expectEqual(state(latest: 0.1199), .ok(0.1199))
    }

    func testReplyAtTheThresholdIsSlow() {
        expectEqual(state(latest: 0.120), .slow(0.120))
    }

    func testReplyAboveTheThresholdIsSlow() {
        expectEqual(state(latest: 0.400), .slow(0.400))
    }

    func testNoReadingYetIsWaiting() {
        expectEqual(state(latest: nil), .waiting)
    }

    func testASingleLossKeepsTheLastReading() {
        expectEqual(state(latest: 0.02, failureStreak: 1), .ok(0.02))
    }

    func testRepeatedLossGoesOffline() {
        expectEqual(state(latest: 0.02, failureStreak: 2), .offline)
        expectEqual(state(latest: 0.02, failureStreak: 9), .offline)
    }

    func testAnUnsatisfiedPathIsAlwaysOffline() {
        expectEqual(state(latest: 0.01, pathSatisfied: false), .offline)
        expectEqual(state(latest: 0.01, dnsFailing: true, pathSatisfied: false), .offline)
        expectEqual(state(latest: nil, pathSatisfied: false), .offline)
    }

    func testBrokenNamesWithALiveHostIsDNS() {
        expectEqual(state(latest: 0.02, dnsFailing: true), .dns)
    }

    func testBrokenNamesBeforeAnyReplyIsDNS() {
        expectEqual(state(latest: nil, dnsFailing: true), .dns)
    }

    func testNothingAnsweringIsOfflineRatherThanDNS() {
        expectEqual(state(latest: nil, failureStreak: 4, dnsFailing: true), .offline)
    }

    func testAStricterPolicyGoesOfflineSooner() {
        let strict = StatusPolicy(warn: 0.120, failuresBeforeOffline: 1)
        expectEqual(
            strict.state(latest: 0.02, failureStreak: 1, dnsFailing: false, pathSatisfied: true),
            .offline)
    }

    func testLatencyIsOnlyCarriedByTheReplyStates() {
        expectEqual(PingState.ok(0.5).latency, 0.5)
        expectEqual(PingState.slow(0.5).latency, 0.5)
        expectNil(PingState.waiting.latency)
        expectNil(PingState.dns.latency)
        expectNil(PingState.offline.latency)
    }

    private func state(
        latest: TimeInterval?,
        failureStreak: Int = 0,
        dnsFailing: Bool = false,
        pathSatisfied: Bool = true
    ) -> PingState {
        policy.state(
            latest: latest,
            failureStreak: failureStreak,
            dnsFailing: dnsFailing,
            pathSatisfied: pathSatisfied)
    }
}

final class SamplesTests: TestCase {
    func testAnEmptyWindowHasNothingToReport() {
        let samples = Samples(window: 60)
        expectNil(samples.average)
        expectNil(samples.minimum)
        expectNil(samples.maximum)
        expectNil(samples.latest)
        expectNil(samples.lastReceived)
        expectNil(samples.end)
        expectNil(samples.start)
        expectEqual(samples.total, 0)
        expectEqual(samples.lost, 0)
        expectEqual(samples.loss, 0)
    }

    func testStatisticsIgnoreLostProbes() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 100)
        samples.append(nil, at: 102)
        samples.append(0.030, at: 104)

        expectEqual(samples.average ?? 0, 0.020, accuracy: 1e-9)
        expectEqual(samples.minimum, 0.010)
        expectEqual(samples.maximum, 0.030)
        expectEqual(samples.total, 3)
        expectEqual(samples.lost, 1)
        expectEqual(samples.loss, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testProbesOlderThanTheWindowFallOut() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 100)
        samples.append(0.020, at: 130)
        samples.append(0.030, at: 165)

        expectEqual(samples.total, 2)
        expectEqual(samples.minimum, 0.020)
        expectEqual(samples.latest, 0.030)
    }

    func testAProbeExactlyOnTheEdgeFallsOut() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 100)
        samples.append(0.020, at: 160)
        expectEqual(samples.total, 1)
    }

    func testAProbeJustInsideTheEdgeIsKept() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 100)
        samples.append(0.020, at: 159.9)
        expectEqual(samples.total, 2)
    }

    func testTheWindowIsAnchoredToTheNewestProbe() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 500)
        samples.append(0.020, at: 530)
        expectEqual(samples.end, 530)
        expectEqual(samples.start, 470)
    }

    func testLastReceivedSurvivesALoss() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 10)
        samples.append(nil, at: 12)
        expectNil(samples.latest)
        expectEqual(samples.lastReceived, 0.010)
    }

    func testLastReceivedTracksTheNewestReply() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 10)
        samples.append(nil, at: 12)
        samples.append(0.030, at: 14)
        expectEqual(samples.lastReceived, 0.030)
    }

    func testATotalBlackoutHasNoLatency() {
        var samples = Samples(window: 60)
        for tick in 0..<30 { samples.append(nil, at: TimeInterval(tick) * 2) }
        expectNil(samples.average)
        expectNil(samples.lastReceived)
        expectEqual(samples.loss, 1)
        expectEqual(samples.lost, 30)
    }

    func testAPerfectMinuteHasNoLoss() {
        var samples = Samples(window: 60)
        for tick in 0..<30 { samples.append(0.01, at: TimeInterval(tick) * 2) }
        expectEqual(samples.loss, 0)
        expectEqual(samples.lost, 0)
    }

    func testTheWindowHoldsAMinuteOfTwoSecondProbes() {
        var samples = Samples(window: 60)
        for tick in 0..<200 { samples.append(0.01, at: TimeInterval(tick) * 2) }
        expectAtLeast(samples.total, 30)
        expectAtMost(samples.total, 31)
    }

    func testClearingEmptiesTheWindow() {
        var samples = Samples(window: 60)
        samples.append(0.01, at: 1)
        samples.clear()
        expectEqual(samples.total, 0)
        expectNil(samples.lastReceived)
    }

    func testASlowIntervalStillKeepsAMinute() {
        var samples = Samples(window: 60)
        for tick in 0..<10 { samples.append(0.01, at: TimeInterval(tick) * 10) }
        expectEqual(samples.total, 6, "a 10s interval leaves six probes in a minute")
    }

    func testASampleKnowsWhetherItWasLost() {
        expectTrue(Sample(at: 0, value: nil).lost)
        expectFalse(Sample(at: 0, value: 0.01).lost)
    }
}

final class LatencyGraphTests: TestCase {
    func testTheScaleNeverTightensBelowTheSlowThreshold() {
        var samples = Samples(window: 60)
        samples.append(0.002, at: 10)
        samples.append(0.003, at: 12)
        expectEqual(LatencyGraph(samples: samples, warn: 0.120).ceiling ?? 0, 0.150, accuracy: 1e-9)
    }

    func testTheScaleFollowsTheSlowestReply() {
        var samples = Samples(window: 60)
        samples.append(0.010, at: 10)
        samples.append(0.400, at: 12)
        expectEqual(LatencyGraph(samples: samples, warn: 0.120).ceiling ?? 0, 0.400, accuracy: 1e-9)
    }

    func testThereIsNoScaleWithoutAReply() {
        var samples = Samples(window: 60)
        samples.append(nil, at: 10)
        expectNil(LatencyGraph(samples: samples, warn: 0.120).ceiling)
        expectNil(LatencyGraph(samples: Samples(window: 60), warn: 0.120).ceiling)
    }

    func testTheTraceBreaksAtEveryLoss() {
        let values: [TimeInterval?] = [0.01, 0.02, nil, nil, 0.03, nil, 0.04, 0.05]
        let samples = values.enumerated().map { Sample(at: TimeInterval($0.offset), value: $0.element) }
        let runs = LatencyGraph.runs(of: samples)
        expectEqual(runs.map(\.count), [2, 1, 2])
        expectEqual(runs.map { $0.map(\.value) }, [[0.01, 0.02], [0.03], [0.04, 0.05]])
    }

    func testAnUnbrokenStretchIsASingleRun() {
        let samples = (0..<5).map { Sample(at: TimeInterval($0), value: 0.01) }
        expectEqual(LatencyGraph.runs(of: samples).count, 1)
        expectEqual(LatencyGraph.runs(of: samples).first?.count, 5)
    }

    func testNothingButLossHasNoRuns() {
        let samples = (0..<5).map { Sample(at: TimeInterval($0), value: nil) }
        expectTrue(LatencyGraph.runs(of: samples).isEmpty)
    }

    func testLeadingAndTrailingLossesProduceNoEmptyRuns() {
        let values: [TimeInterval?] = [nil, 0.01, nil]
        let samples = values.enumerated().map { Sample(at: TimeInterval($0.offset), value: $0.element) }
        expectEqual(LatencyGraph.runs(of: samples).map(\.count), [1])
    }

    func testAnEmptyWindowHasNoRuns() {
        expectTrue(LatencyGraph.runs(of: []).isEmpty)
    }
}

final class SignalGraphTests: TestCase {
    func testQualitySpansTheUsableRange() {
        expectEqual(SignalScale.quality(-100), 0, accuracy: 1e-9)
        expectEqual(SignalScale.quality(-75), 0.5, accuracy: 1e-9)
        expectEqual(SignalScale.quality(-50), 1, accuracy: 1e-9)
    }

    func testQualityClampsOutsideTheRange() {
        expectEqual(SignalScale.quality(-120), 0, accuracy: 1e-9)
        expectEqual(SignalScale.quality(-10), 1, accuracy: 1e-9)
    }

    func testTheGoodThresholdSitsInTheUpperHalf() {
        expectGreaterThan(SignalScale.quality(SignalScale.good), 0.5)
        expectLessThan(SignalScale.quality(SignalScale.good), 1)
    }

    func testASnapshotAndTheScaleAgreeOnQuality() {
        var wifi = WiFiSnapshot()
        wifi.rssi = -67
        expectEqual(wifi.quality ?? -1, SignalScale.quality(-67), accuracy: 1e-9)
    }

    func testTheTintFollowsTheLastReading() {
        var samples = Samples(window: SignalGraph.window)
        samples.append(-55, at: 10)
        expectEqual(SignalGraph(samples: samples).tint, SignalScale.tint(SignalScale.quality(-55)))
        samples.append(nil, at: 20)
        expectEqual(SignalGraph(samples: samples).tint, SignalScale.tint(SignalScale.quality(-55)))
    }

    func testAWindowWithoutAReadingFallsBackToTheWeakestTint() {
        var samples = Samples(window: SignalGraph.window)
        samples.append(nil, at: 10)
        expectEqual(SignalGraph(samples: samples).tint, SignalScale.tint(0))
    }

    func testTheWindowHoldsFiveMinutesOfTwoSecondSamples() {
        var samples = Samples(window: SignalGraph.window)
        for tick in 0..<400 { samples.append(-60, at: TimeInterval(tick) * 2) }
        expectAtLeast(samples.total, 150)
        expectAtMost(samples.total, 151)
    }

    func testTheTraceBreaksWhereTheRadioWentQuiet() {
        let values: [Double?] = [-60, -62, nil, -58]
        let samples = values.enumerated().map { Sample(at: TimeInterval($0.offset), value: $0.element) }
        expectEqual(LatencyGraph.runs(of: samples).map(\.count), [2, 1])
    }
}
