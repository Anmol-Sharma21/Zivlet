import EngineTestSupport
import Foundation
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// A batch holds each job's passwords for that job's life, one crash retry included, and wipes them when the job ends
/// (plan 20f E3, D-M7-14). A secret several jobs share is wiped when the last of them ends.
@Suite("A batch's passwords live as long as their jobs")
struct BatchSecretsTests {
    let password = "zv-batch-" + UUID().uuidString

    static func protect(_ box: Sandbox, _ name: String, _ mode: ProtectSpec.Mode = .unlock) throws -> JobRequest {
        try box.file(name, "%PDF-1.7\n")
        let input = try InputItem(url: box.dir.appending(path: name), format: .pdf, byteCount: 9)
        return try JobRequest(input: input, operation: .protect(ProtectSpec(mode: mode)), destination: box.dir)
    }

    static func scheduler(_ engine: any Engine) -> JobScheduler {
        JobScheduler(
            engines: [engine], lanes: .standard(performanceCores: 4), records: nil, processes: SystemProcesses(),
            clock: { .zero })
    }

    static func zeroed(_ secret: JobSecret) -> Bool {
        secret.isWiped && secret.withBytes { $0.allSatisfy { $0 == 0 } }
    }

    @Test func aSharedSecretIsWipedWhenItsLastJobEnds() {
        let shared = JobSecrets(input: JobSecret(utf8: password))
        let (one, two) = (JobID(), JobID())
        let batch = BatchSecrets.shared(shared, for: [one, two])
        #expect(batch.secrets(for: one) == shared)
        batch.release(one)
        #expect(shared.input?.isWiped == false)
        #expect(batch.secrets(for: one) == nil)
        batch.release(two)
        #expect(Self.zeroed(try! #require(shared.input)))
    }

    @Test func eachStepOfAJobGetsItsPasswordAndTheBatchWipesItAfterwards() async throws {
        let box = try Sandbox()
        let engine = SecretEngine()
        let scheduler = Self.scheduler(engine)
        let request = try Self.protect(box, "Report.pdf")
        let secrets = JobSecrets(input: JobSecret(utf8: password))
        let batch = await scheduler.submit(
            [request], secrets: BatchSecrets.shared(secrets, for: [request.id]))
        let events = await scheduler.collect(until: batch)
        await scheduler.waitUntilIdle()

        #expect(events.states(of: request.id).last?.published?.url.lastPathComponent == "Report Unlocked.pdf")
        #expect(engine.seen.map(\.step) == ["prepare", "execute", "verify"])
        #expect(engine.seen.allSatisfy { $0.input == Array(password.utf8) })
        #expect(engine.secretsGiven.allSatisfy(Self.zeroed))
    }

    @Test(arguments: [
        SecretEngine.Behaviour.fail(.verificationFailed("x")), .crashOnce, .succeed,
    ])
    func theSecretsReadZeroAfterTheJobEnds(behaviour: SecretEngine.Behaviour) async throws {
        let box = try Sandbox()
        let engine = SecretEngine(behaviour)
        let scheduler = Self.scheduler(engine)
        let requests = try [Self.protect(box, "a.pdf"), Self.protect(box, "b.pdf")]
        let secret = JobSecret(utf8: password)
        let batch = await scheduler.submit(
            requests, secrets: BatchSecrets.shared(JobSecrets(input: secret), for: requests.map(\.id)))
        _ = await scheduler.collect(until: batch)
        await scheduler.waitUntilIdle()

        #expect(Self.zeroed(secret))
        // A crashed attempt's retry still had the password: it is held for the job, not for one attempt.
        #expect(engine.seen.filter { $0.step == "execute" }.allSatisfy { $0.input == Array(password.utf8) })
    }

    @Test func aCancelledJobsSecretsReadZero() async throws {
        let box = try Sandbox()
        let engine = SecretEngine(.waitUntilCancelled)
        let scheduler = Self.scheduler(engine)
        let request = try Self.protect(box, "a.pdf")
        let secret = JobSecret(utf8: password)
        let batch = await scheduler.submit(
            [request], secrets: BatchSecrets.shared(JobSecrets(input: secret), for: [request.id]))
        await engine.reachedExecute.wait()
        await scheduler.cancel(batch: batch)
        await scheduler.waitUntilIdle()
        #expect(Self.zeroed(secret))
    }

    @Test func aJobWithoutSecretsGetsNone() async throws {
        let box = try Sandbox()
        let engine = SecretEngine()
        let scheduler = Self.scheduler(engine)
        let request = try Self.protect(box, "a.pdf", .lock(nil))
        _ = await scheduler.collect(until: await scheduler.submit([request]))
        #expect(engine.seen.allSatisfy { $0.input == nil && $0.newUser == nil })
    }

    /// The password crosses the loopback worker inside each request of its job and nowhere else.
    @Test func theWorkersEngineGetsTheBytesThroughEachRequest() async throws {
        let box = try Sandbox()
        let engine = SecretEngine()
        let transport = LoopbackTransport(service: WorkerService(engines: [engine], onIdle: {}))
        let connection = WorkerConnection(transport: transport)
        let capability = try #require(try await connection.capabilities().engine(.pdf))
        #expect(capability.handles(ConversionPair(source: .pdf, target: .pdf)))
        let scheduler = Self.scheduler(RemoteEngine(capability: capability, connection: connection))
        let request = try Self.protect(box, "Report.pdf")
        let secret = JobSecret(utf8: password)
        let batch = await scheduler.submit(
            [request], secrets: BatchSecrets.shared(JobSecrets(input: secret), for: [request.id]))
        let events = await scheduler.collect(until: batch)
        await scheduler.waitUntilIdle()

        #expect(events.states(of: request.id).last?.published != nil)
        #expect(engine.seen.map(\.step) == ["prepare", "execute", "verify"])
        #expect(engine.seen.allSatisfy { $0.input == Array(password.utf8) })
        // The worker's copies are wiped when each step ends, the app's when the job ends.
        #expect(engine.secretsGiven.allSatisfy(Self.zeroed))
        #expect(Self.zeroed(secret))
    }

    /// G-M7-19: with no worker, a PDF tool job fails as a missing engine rather than running anywhere else.
    @Test func aPDFToolJobWithTheWorkerDownFailsWithTheEngineMissing() async throws {
        let box = try Sandbox()
        let unused = WorkerConnection(transport: LoopbackTransport(service: WorkerService(engines: [], onIdle: {})))
        let selection = WorkerSelection(workerBundle: nil, verify: { _ in }, connection: unused)
        let scheduler = Self.scheduler(WorkerOnlyEngine(id: .pdf, pairs: [.protectPDF], selection: selection))
        let request = try Self.protect(box, "a.pdf")
        let events = await scheduler.collect(until: await scheduler.submit([request]))
        #expect(events.states(of: request.id).last == .failed(.engineMissing(.pdf)))
    }
}
