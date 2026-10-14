import Testing
@testable import MemoryCore

@Suite struct MetricHistoryTests {
    private func history(_ times: ClosedRange<Int>, span: Double = 3600) -> MetricHistory {
        var history = MetricHistory(span: span)
        for t in times { history.append([Double(t), 1], at: Double(t)) }
        return history
    }

    @Test func dropsSamplesOlderThanSpan() {
        let history = history(0...1000, span: 100)
        #expect(history.samples.first!.time >= 1000 - 100 - 10)
        #expect(history.samples.last!.time == 1000)
        #expect(history.samples.count <= 111)
    }

    @Test func ignoresOutOfOrderSamples() {
        var history = history(0...5)
        history.append([9, 9], at: 3)
        #expect(history.samples.count == 6)
        #expect(history.samples.last!.time == 5)
    }

    @Test func returnsEveryPointWhenTheyFit() {
        let segments = history(0...59).segments(from: 0, to: 60, maxPoints: 60, maxGap: 3)
        #expect(segments.count == 1)
        #expect(segments[0].count == 60)
        #expect(segments[0][10].values == [10, 1])
    }

    @Test func averagesIntoBuckets() {
        // An hour of 1-second samples into 600 buckets: six samples each.
        let segments = history(0...3599).segments(from: 0, to: 3600, maxPoints: 600, maxGap: 3)
        #expect(segments.count == 1)
        #expect(segments[0].count == 600)
        #expect(segments[0][0].values == [2.5, 1]) // mean of 0...5
        #expect(segments[0][0].time == 2.5)
    }

    @Test func onlyIncludesTheRequestedWindow() {
        let segments = history(0...999).segments(from: 900, to: 960, maxPoints: 60, maxGap: 3)
        // 61 samples (900...960) in 60 buckets: the last bucket averages 959 and 960.
        #expect(segments[0].first!.time == 900)
        #expect(segments[0].last!.time == 959.5)
        #expect(segments[0].count == 60)
    }

    @Test func splitsAtGaps() {
        var history = history(0...9)
        for t in 100...109 { history.append([Double(t), 1], at: Double(t)) } // the Mac slept
        let segments = history.segments(from: 0, to: 110, maxPoints: 110, maxGap: 3)
        #expect(segments.count == 2)
        #expect(segments.map(\.count) == [10, 10])
    }

    @Test func emptyWindowGivesNoSegments() {
        #expect(history(0...9).segments(from: 50, to: 60, maxPoints: 10, maxGap: 3).isEmpty)
        #expect(MetricHistory(span: 60).segments(from: 0, to: 60, maxPoints: 10, maxGap: 3).isEmpty)
    }

    @Test func totalAddsTheStack() {
        #expect(MetricHistory.Point(time: 0, values: [0.25, 0.5, 0.125]).total == 0.875)
    }
}
