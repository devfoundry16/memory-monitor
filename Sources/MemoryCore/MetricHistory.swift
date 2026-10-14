/// A rolling record of a few related values over time, such as app memory, wired and
/// compressed, for drawing as a stacked graph.
public struct MetricHistory: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        /// Seconds on a clock that keeps running while the Mac sleeps, so sleep shows as a gap.
        public var time: Double
        public var values: [Double]

        public init(time: Double, values: [Double]) {
            self.time = time
            self.values = values
        }

        public var total: Double { values.reduce(0, +) }
    }

    /// How far back samples are kept, in seconds.
    public let span: Double
    /// Oldest first.
    public private(set) var samples: [Point] = []

    public init(span: Double) {
        self.span = span
    }

    public mutating func append(_ values: [Double], at time: Double) {
        if let last = samples.last, time <= last.time { return }
        samples.append(Point(time: time, values: values))
        // Trim in batches so appending stays cheap.
        let cutoff = time - span
        if let first = samples.first, first.time < cutoff - span / 10 {
            samples.removeFirst(samples.partitioningIndex { $0.time >= cutoff })
        }
    }

    /// The samples from `start` to `end`, averaged into at most `maxPoints` equal time buckets
    /// and split wherever no sample arrived for longer than `maxGap` seconds.
    public func segments(from start: Double, to end: Double, maxPoints: Int, maxGap: Double) -> [[Point]] {
        guard end > start, maxPoints > 0 else { return [] }
        let window = samples[samples.partitioningIndex { $0.time >= start }...].prefix { $0.time <= end }
        let width = (end - start) / Double(maxPoints)

        var buckets: [Point] = []
        var sum: [Double] = [], timeSum = 0.0, count = 0, bucket = -1
        func flush() {
            guard count > 0 else { return }
            buckets.append(Point(time: timeSum / Double(count), values: sum.map { $0 / Double(count) }))
        }
        for point in window {
            let index = min(Int((point.time - start) / width), maxPoints - 1)
            if index != bucket {
                flush()
                bucket = index
                sum = point.values
                timeSum = point.time
                count = 1
            } else {
                for i in sum.indices where i < point.values.count { sum[i] += point.values[i] }
                timeSum += point.time
                count += 1
            }
        }
        flush()

        let gap = max(maxGap, width * 2)
        var result: [[Point]] = []
        for point in buckets {
            if let previous = result.last?.last, point.time - previous.time <= gap {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }
}

extension RandomAccessCollection {
    /// The first index where `predicate` is true, for a collection where it is false and then
    /// true (such as samples sorted by time).
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var low = startIndex, high = endIndex
        while low < high {
            let mid = index(low, offsetBy: distance(from: low, to: high) / 2)
            if predicate(self[mid]) { high = mid } else { low = index(after: mid) }
        }
        return low
    }
}
