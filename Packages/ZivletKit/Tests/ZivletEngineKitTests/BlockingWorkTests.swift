import Foundation
import Testing
import ZivletCore

@testable import ZivletEngineKit

@Suite("BlockingWork: off the cooperative pool, typed errors, cancellation flag")
struct BlockingWorkTests {
    @Test func returnsTheValueFromAGCDThread() async throws {
        let onMain = try await BlockingWork.run { _ in Thread.isMainThread }
        #expect(!onMain)
    }

    @Test func rethrowsTheTypedError() async {
        await #expect(throws: JobError.diskFull) {
            try await BlockingWork.run { _ throws(JobError) -> Int in throw .diskFull }
        }
    }

    @Test func cancellingTheCallerSetsTheFlag() async throws {
        let task = Task {
            try await BlockingWork.run { flag throws(JobError) -> Bool in
                for _ in 0..<500 where !flag.isCancelled { Thread.sleep(forTimeInterval: 0.01) }
                if flag.isCancelled { throw .cancelled }
                return false
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: JobError.cancelled) { try await task.value }
    }
}
