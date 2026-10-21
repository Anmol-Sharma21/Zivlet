import Dispatch
import Foundation
import Synchronization
import ZivletEngineKit

/// What the system says about memory and power, the input to lane limits (03a §4.2, 10 §8.1).
public struct SystemLoad: Sendable, Equatable {
    public enum Memory: Sendable, Equatable { case normal, warning, critical }

    public let memory: Memory
    public let lowPower: Bool

    public init(memory: Memory = .normal, lowPower: Bool = false) {
        self.memory = memory
        self.lowPower = lowPower
    }
}

/// Pure lane limits for a load: a memory warning halves every lane, critical memory pauses admission (0), Low Power
/// halves the `cpu` lane. Halving never goes below one permit.
public struct LaneLimits: Sendable, Equatable {
    private let limits: [Lane: Int]

    public init(base: LaneWidths, load: SystemLoad) {
        let widths = load.memory == .warning ? base.halved() : base
        limits = Dictionary(
            uniqueKeysWithValues: Lane.allCases.map { lane in
                let width = widths.width(lane)
                switch (load.memory, lane) {
                case (.critical, _): return (lane, 0)
                case (_, .cpu) where load.lowPower: return (lane, max(1, width / 2))
                default: return (lane, width)
                }
            })
    }

    public func limit(_ lane: Lane) -> Int { limits[lane] ?? 1 }
}

/// Live system load: the kernel's memory pressure events and the Low Power Mode notification, as a stream of values.
/// Thin glue; the rules are in `LaneLimits`.
public final class SystemLoadMonitor: Sendable {
    public let loads: AsyncStream<SystemLoad>
    private let continuation: AsyncStream<SystemLoad>.Continuation
    private let source: any DispatchSourceMemoryPressure
    /// Only read in `deinit` to unregister.
    private nonisolated(unsafe) let observer: any NSObjectProtocol
    private let state = LoadState()

    public init() {
        (loads, continuation) = AsyncStream.makeStream(of: SystemLoad.self, bufferingPolicy: .bufferingNewest(1))
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global())
        let (source, state, continuation) = (source, state, continuation)
        source.setEventHandler {
            let event = source.data
            let memory: SystemLoad.Memory =
                event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            continuation.yield(state.update { SystemLoad(memory: memory, lowPower: $0.lowPower) })
        }
        source.activate()
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { _ in
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            continuation.yield(state.update { SystemLoad(memory: $0.memory, lowPower: lowPower) })
        }
        continuation.yield(
            state.update { SystemLoad(memory: $0.memory, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) })
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
        source.cancel()
        continuation.finish()
    }
}

/// The latest load, shared by the two event sources.
private final class LoadState: Sendable {
    private let value = Mutex(SystemLoad())

    func update(_ change: (SystemLoad) -> SystemLoad) -> SystemLoad {
        value.withLock { current in
            current = change(current)
            return current
        }
    }
}
