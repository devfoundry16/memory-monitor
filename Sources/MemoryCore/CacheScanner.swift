import Foundation

public enum ScanEvent: Sendable {
    case discovered(CacheDiscovery.Result)
    case sized(CacheItem.ID, CacheSize)
    case finished
}

/// Finds caches, then measures them a few at a time in the background, streaming each size
/// as it's known. Cancelling the task that reads the stream stops the work.
public struct CacheScanner: Sendable {
    public let environment: CacheEnvironment
    private let concurrency: Int

    public init(environment: CacheEnvironment = .current, concurrency: Int = 4) {
        self.environment = environment
        self.concurrency = max(1, concurrency)
    }

    public func scan() -> AsyncStream<ScanEvent> {
        stream { [environment, concurrency] continuation in
            let index = AppIndex(scanning: environment.applicationDirectories)
            let result = CacheDiscovery(environment: environment, appIndex: index).discover()
            continuation.yield(.discovered(result))
            await Self.measure(result.items, concurrency: concurrency, into: continuation)
        }
    }

    /// Measures `items` again, e.g. after cleaning.
    public func measure(_ items: [CacheItem]) -> AsyncStream<ScanEvent> {
        stream { [concurrency] continuation in
            await Self.measure(items, concurrency: concurrency, into: continuation)
        }
    }

    public static func size(of item: CacheItem) -> CacheSize {
        FileTreeWalker.measure(item.targets.flatMap { $0.removableEntries() }, isCancelled: { Task.isCancelled })
    }

    private func stream(
        _ body: @escaping @Sendable (AsyncStream<ScanEvent>.Continuation) async -> Void
    ) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                await body(continuation)
                if !Task.isCancelled { continuation.yield(.finished) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func measure(
        _ items: [CacheItem], concurrency: Int, into continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        await withTaskGroup(of: (CacheItem.ID, CacheSize).self) { group in
            var pending = items[...]
            for _ in 0..<concurrency {
                guard let item = pending.popFirst() else { break }
                group.addTask { (item.id, size(of: item)) }
            }
            while let (id, size) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                continuation.yield(.sized(id, size))
                if let item = pending.popFirst() {
                    group.addTask { (item.id, Self.size(of: item)) }
                }
            }
        }
    }
}
