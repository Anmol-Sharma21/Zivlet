import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

@Suite("JobScheduler with a fake engine and a frozen clock (P1-31, 03a §4.1–4.6)")
struct JobSchedulerTests {
    static func scheduler(
        _ engine: FakeEngine, lanes: LaneWidths = .standard(performanceCores: 4), records: JobRecordStore? = nil
    )
        -> JobScheduler
    {
        JobScheduler(
            engines: [engine], lanes: lanes, records: records, processes: SystemProcesses(), clock: { .zero })
    }

    @Test func aJobRunsEveryStepAndPublishes() async throws {
        let box = try Sandbox()
        try box.file("photo.heic")
        let engine = FakeEngine(notes: [.alphaFlattened]) { _, context throws(JobError) in
            context.progress.report(0.4)
            context.progress.report(1)
        }
        let scheduler = Self.scheduler(engine)
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let batch = await scheduler.submit([request])
        let events = await scheduler.collect(until: batch)
        let states = events.states(of: request.id)
        let output = try #require(states.last?.published, "not published: \(states)")
        #expect(output.url.lastPathComponent == "photo.jpg" && output.byteCount == 3)
        #expect(
            states.dropLast() == [
                .queued, .preparing, .running(JobProgress(fraction: 0)), .running(JobProgress(fraction: 1)), .verifying,
                .publishing,
            ])
        #expect(events.first == .submitted(batch, [request]))
        #expect(events.contains(.noted(batch, request.id, [.alphaFlattened])))
        #expect(box.listing == ["photo.heic", "photo.jpg"])
    }

    @Test func failuresAreIsolatedPerFileAndLeaveNoStaging() async throws {
        let box = try Sandbox()
        let bad = FakeEngine(verifyError: .verificationFailed("no audio"))
        let scheduler = Self.scheduler(bad)
        let one = try box.request("a.heic", .heic, to: .jpg)
        let two = try box.request("b.heic", .heic, to: .png)
        let batch = await scheduler.submit([one, two])
        let events = await scheduler.collect(until: batch)
        #expect(events.states(of: one.id).last == .failed(.verificationFailed("no audio")))
        #expect(events.states(of: two.id).last == .failed(.verificationFailed("no audio")))
        await scheduler.waitUntilIdle()
        #expect(box.listing.isEmpty)
    }

    @Test(arguments: [
        (FakeEngine(prepareError: .unsupportedInput(.unreadable)), JobError.unsupportedInput(.unreadable)),
        (FakeEngine(availability: .unavailable(["libwebp"])), .routeUnavailable(.png, .webp, ["libwebp"])),
    ])
    func preparationFailuresAreTyped(engine: FakeEngine, expected: JobError) async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(engine)
        let request = try box.request("a.png", .png, to: .webp)
        let batch = await scheduler.submit([request])
        #expect(await scheduler.collect(until: batch).states(of: request.id).last == .failed(expected))
    }

    @Test func aPairNoEngineHandlesIsRefused() async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(FakeEngine())
        let request = try box.request("a.mp3", .mp3, to: .wav)
        let batch = await scheduler.submit([request])
        #expect(
            await scheduler.collect(until: batch).states(of: request.id).last == .failed(.pairNotSupported(.mp3, .wav)))
    }

    @Test(arguments: [(Lane.swVideo, 1), (.cpu, 3), (.remux, 4)])
    func laneWidthsBoundConcurrency(lane: Lane, width: Int) async throws {
        let box = try Sandbox()
        let meter = ConcurrencyMeter()
        let engine = FakeEngine(lane: lane) { _, _ throws(JobError) in
            meter.enter()
            try? await Task.sleep(for: .milliseconds(20))
            meter.leave()
        }
        let scheduler = Self.scheduler(engine, lanes: .standard(performanceCores: 3))
        let requests = try (0..<12).map { _ in try box.request("a.heic", .heic, to: .jpg) }
        let batch = await scheduler.submit(requests)
        _ = await scheduler.collect(until: batch)
        #expect(meter.peak == width)
    }

    /// Preparing probes the input with a helper (two pipe descriptors each); a big drop must not start one per file
    /// at once, or a GUI app's 256-descriptor limit runs out (EMFILE).
    @Test func preparationIsBoundedAcrossABatch() async throws {
        let box = try Sandbox()
        let meter = ConcurrencyMeter()
        var engine = FakeEngine()
        engine.onPrepare = {
            meter.enter()
            try? await Task.sleep(for: .milliseconds(10))
            meter.leave()
        }
        let scheduler = Self.scheduler(engine, lanes: .standard(performanceCores: 16))
        let requests = try (0..<40).map { _ in try box.request("a.heic", .heic, to: .jpg) }
        _ = await scheduler.collect(until: await scheduler.submit(requests))
        #expect(meter.peak == LaneGates.preparationWidth)
    }

    @Test func cancelIsVisibleAtOnceAndRemovesStaging() async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(FakeEngine(body: FakeEngine.waitsForCancel))
        let request = try box.request("clip.mov", .mov, to: .mp4)
        let batch = await scheduler.submit([request])
        var iterator = scheduler.events.makeAsyncIterator()
        while let event = await iterator.next(),
            event != .changed(batch, request.id, .running(JobProgress(fraction: 0)))
        {}
        let start = ContinuousClock.now
        await scheduler.cancel(job: request.id)
        #expect(await iterator.next() == .changed(batch, request.id, .cancelled))
        #expect(ContinuousClock.now - start < .milliseconds(100))
        #expect(await iterator.next() == .finished(batch))
        await scheduler.waitUntilIdle()
        #expect(box.listing.isEmpty)
    }

    /// 03a §4.3/4.6: a cancelled job is never published, and a published job is never reported cancelled.
    @Test func cancelDuringPublishingNeverLeavesACancelledJobsOutputOnDisk() async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(FakeEngine())
        let requests = try (0..<60).map { _ in try box.request("a.jpg", .jpg, to: .png) }
        let batch = await scheduler.submit(requests)
        var events: [JobEvent] = []
        for await event in scheduler.events {
            events.append(event)
            if case .changed(_, let job, .publishing) = event { await scheduler.cancel(job: job) }
            if event == .finished(batch) { break }
        }
        await scheduler.waitUntilIdle()
        let finals = requests.map { events.states(of: $0.id).last }
        let published = finals.compactMap { $0?.published?.url.lastPathComponent }
        let outputs = box.listing.filter { $0.hasSuffix(".png") }
        #expect(Set(outputs) == Set(published), "\(finals.filter { $0 == .cancelled }.count) cancelled")
    }

    @Test func cancellingABatchCancelsEveryJobInIt() async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(FakeEngine(body: FakeEngine.waitsForCancel))
        let requests = try (0..<3).map { _ in try box.request("a.heic", .heic, to: .png) }
        let batch = await scheduler.submit(requests)
        await scheduler.cancel(batch: batch)
        let events = await scheduler.collect(until: batch)
        #expect(requests.allSatisfy { events.states(of: $0.id).last == .cancelled })
        await scheduler.waitUntilIdle()
        #expect(box.listing.isEmpty)
    }

    @Test func twoHundredJobsForOneNameGetDistinctOutputs() async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(FakeEngine())
        let requests = try (0..<200).map { _ in try box.request("a.jpg", .jpg, to: .png) }
        let batch = await scheduler.submit(requests)
        let events = await scheduler.collect(until: batch)
        let names = Set(requests.compactMap { events.states(of: $0.id).last?.published?.url.lastPathComponent })
        #expect(names.count == 200 && names.contains("a.png") && names.contains("a 200.png"))
    }

    @Test func aRunningJobIsRecordedWithItsChildAndForgottenAfter() async throws {
        let box = try Sandbox()
        let store = JobRecordStore(directory: box.dir.appending(path: "Jobs"))
        let seen = Mutex<[JobRecord]>([])
        let engine = FakeEngine { _, context throws(JobError) in
            context.spawned(getpid())
            seen.withLock { $0 = store.all() }
        }
        let scheduler = Self.scheduler(engine, records: store)
        let request = try box.request("a.heic", .heic, to: .jpg)
        _ = await scheduler.collect(until: await scheduler.submit([request]))
        let record = try #require(seen.withLock { $0 }.first)
        #expect(record.job == request.id && record.childPID == getpid() && record.childPath != nil)
        #expect(store.all().isEmpty)
    }

    @Test func aStagingFileThatCannotBeRemovedKeepsItsRecordForTheReaper() async throws {
        let box = try Sandbox()
        let folder = box.dir.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let store = JobRecordStore(directory: box.dir.appending(path: "Jobs"))
        let engine = FakeEngine { _, _ throws(JobError) in
            try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
            throw .processFailed(status: 1, stderrTail: "")
        }
        let scheduler = Self.scheduler(engine, records: store)
        let input = try InputItem(url: box.dir.appending(path: "a.heic"), format: .heic, byteCount: 4)
        let request = try JobRequest(input: input, operation: .convert(.jpg), destination: folder)
        _ = await scheduler.collect(until: await scheduler.submit([request]))
        await scheduler.waitUntilIdle()
        #expect(store.all().map(\.job) == [request.id])
    }

    @Test func shutdownCancelsEverythingWithinTheLimit() async throws {
        let box = try Sandbox()
        let scheduler = Self.scheduler(FakeEngine(body: FakeEngine.waitsForCancel))
        await scheduler.submit(try (0..<3).map { _ in try box.request("a.heic", .heic, to: .jpg) })
        #expect(await scheduler.shutdown(within: .seconds(2)))
        #expect(box.listing.isEmpty)
    }

    @Test func shutdownGivesUpAtTheLimitWhenAJobIgnoresCancel() async throws {
        let box = try Sandbox()
        let engine = FakeEngine { _, _ throws(JobError) in
            await withCheckedContinuation { done in
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { done.resume() }
            }
        }
        let scheduler = Self.scheduler(engine)
        let request = try box.request("a.heic", .heic, to: .jpg)
        let batch = await scheduler.submit([request])
        var iterator = scheduler.events.makeAsyncIterator()
        while let event = await iterator.next(),
            event != .changed(batch, request.id, .running(JobProgress(fraction: 0)))
        {}
        let start = ContinuousClock.now
        #expect(await scheduler.shutdown(within: .milliseconds(200)) == false)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func anEmptySubmissionFinishesImmediately() async {
        let scheduler = Self.scheduler(FakeEngine())
        let batch = await scheduler.submit([])
        #expect(await scheduler.collect(until: batch) == [.submitted(batch, []), .finished(batch)])
        await scheduler.cancel(job: JobID())
    }
}
