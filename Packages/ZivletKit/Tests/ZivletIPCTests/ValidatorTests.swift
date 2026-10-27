import EngineVision
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

/// Real files in a temporary folder: an input, a directory, a symlink to a system file and a claimed staging folder.
struct ValidatorRig {
    let dir: TempDir
    let job = JobID()
    let input: URL
    let staged: URL
    let validator = WorkerRequestValidator(hostedEngines: [.image, .vision])

    init() throws {
        dir = try TempDir(prefix: "zivlet-validator")
        input = try dir.file("photo.png")
        let folder = try dir.folder(".zivlet-\(job)")
        staged = folder.appending(path: "staged.jpg")
        try Data().write(to: staged)
        try dir.folder("folder.png")
        try FileManager.default.createSymbolicLink(
            at: dir.url.appending(path: "hosts.png"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    }

    func prepare(input name: String = "photo.png", staged: URL? = nil) throws -> WorkerRequest {
        let item = try InputItem(url: dir.url.appending(path: name), format: .png, byteCount: 4)
        let request = try JobRequest(id: job, input: item, operation: .convert(.jpg), destination: dir.url)
        return .prepare(request, JobWorkspace(job: job, stagedFile: staged ?? self.staged))
    }

    func plan(engine: EngineID = .image, staged: URL? = nil, source: URL? = nil) throws -> ExecutionPlan {
        let spec = try ImagePipelineSpec(
            source: source ?? input, destinationType: "public.jpeg", output: .raster, frames: [0], flattenAlpha: true,
            quality: 0.9, tiffLZW: false, expectedSize: PixelSize(width: 2, height: 2))
        return try ExecutionPlan(
            engine: engine, stages: [.image(spec)], stageWeights: [1], lanes: [.cpu], outputFormat: .jpg,
            stagedFile: staged ?? self.staged)
    }

    func refusal(_ request: WorkerRequest) -> JobError? {
        do {
            try validator.validate(request)
            return nil
        } catch {
            return error
        }
    }
}

@Suite("Every worker request is checked at the boundary (03b, D-M6-4)")
struct ValidatorTests {
    @Test func wellFormedRequestsPass() throws {
        let rig = try ValidatorRig()
        let output = StagedOutput(format: .jpg, url: rig.staged, byteCount: 0)
        for request in [
            try rig.prepare(), .execute(rig.job, try rig.plan(), outputByteLimit: 1_000),
            .execute(rig.job, try rig.plan(), outputByteLimit: nil), .verify(output, try rig.plan()), .ping,
            .capabilities, .cancel(rig.job),
        ] {
            #expect(rig.refusal(request) == nil, "\(request)")
        }
    }

    @Test func aSymlinkOrAFolderIsNotAnInput() throws {
        let rig = try ValidatorRig()
        #expect(rig.refusal(try rig.prepare(input: "hosts.png")) == .unsupportedInput(.notAFile))
        #expect(rig.refusal(try rig.prepare(input: "folder.png")) == .unsupportedInput(.notAFile))
        #expect(rig.refusal(try rig.prepare(input: "missing.png")) == .unsupportedInput(.notAFile))
        let viaSymlink = try rig.plan(source: rig.dir.url.appending(path: "hosts.png"))
        #expect(rig.refusal(.execute(rig.job, viaSymlink, outputByteLimit: nil)) == .unsupportedInput(.notAFile))
    }

    @Test func aStagedFileMustSitInAStagingFolderUnderItsOwnName() throws {
        let rig = try ValidatorRig()
        let loose = rig.dir.url.appending(path: "staged.jpg")
        let renamed = rig.staged.deletingLastPathComponent().appending(path: "output.jpg")
        let unclaimed = rig.dir.url.appending(path: ".zivlet-other/staged.jpg")
        for staged in [loose, renamed, unclaimed] {
            #expect(rig.refusal(try rig.prepare(staged: staged)) == .invalidDestination, "\(staged.path)")
            let output = StagedOutput(format: .jpg, url: staged, byteCount: 0)
            #expect(rig.refusal(.verify(output, try rig.plan())) == .invalidDestination, "\(staged.path)")
        }
    }

    @Test func relativeDottedOrControlPathsAreRefused() throws {
        let rig = try ValidatorRig()
        let dotted = URL(fileURLWithPath: rig.staged.deletingLastPathComponent().path + "/../x/staged.jpg")
        let relative = try #require(URL(string: "staged.jpg"))
        let control = URL(fileURLWithPath: rig.staged.deletingLastPathComponent().path + "/staged\u{1}.jpg")
        let web = try #require(URL(string: "https://example.invalid/staged.jpg"))
        for staged in [dotted, relative, control, web] {
            #expect(rig.refusal(.execute(rig.job, try rig.plan(staged: staged), outputByteLimit: nil)) != nil)
        }
        let dottedSource = URL(fileURLWithPath: rig.dir.url.path + "/x/../photo.png")
        #expect(
            rig.refusal(.execute(rig.job, try rig.plan(source: dottedSource), outputByteLimit: nil))
                == .unsupportedInput(.notAFile))
    }

    @Test func anEngineTheWorkerDoesNotHostIsMissing() throws {
        let rig = try ValidatorRig()
        #expect(
            rig.refusal(.execute(rig.job, try rig.plan(engine: .media), outputByteLimit: nil)) == .engineMissing(.media)
        )
        let output = StagedOutput(format: .jpg, url: rig.staged, byteCount: 0)
        #expect(rig.refusal(.verify(output, try rig.plan(engine: .media))) == .engineMissing(.media))
    }

    @Test func aTextJobNeedsSafeRegularFilesAndLanguages() throws {
        let rig = try ValidatorRig()
        let job = { (inputs: [URL], languages: [LanguageTag]) in
            WorkerRequest.recognizeText(TextJob(id: rig.job, inputs: inputs, languages: languages))
        }
        #expect(rig.refusal(job([rig.input], [.hindi, .english])) == nil)
        #expect(rig.refusal(.textCapabilities) == nil)
        #expect(rig.refusal(.warmUpText([.english])) == nil)
        for name in ["hosts.png", "folder.png"] {
            #expect(rig.refusal(job([rig.dir.url.appending(path: name)], [.english])) == .unsupportedInput(.notAFile))
        }
        guard case .internalInvariant = rig.refusal(job([], [.english])) else {
            Issue.record("an empty job passed")
            return
        }
        guard case .internalInvariant = rig.refusal(job([rig.input], [])) else {
            Issue.record("a job without languages passed")
            return
        }
        let many = Array(repeating: rig.input, count: TextJob.maximumInputs + 1)
        guard case .internalInvariant = rig.refusal(job(many, [.english])) else {
            Issue.record("too many inputs passed")
            return
        }
        guard case .internalInvariant = rig.refusal(.warmUpText([])) else {
            Issue.record("a warm-up without languages passed")
            return
        }
    }

    @Test func aWorkerWithoutVisionRefusesTextJobs() throws {
        let rig = try ValidatorRig()
        let imageOnly = WorkerRequestValidator(hostedEngines: [.image])
        let request = WorkerRequest.recognizeText(TextJob(id: rig.job, inputs: [rig.input], languages: [.english]))
        #expect(throws: JobError.engineMissing(.vision)) { try imageOnly.validate(request) }
        #expect(throws: JobError.engineMissing(.vision)) { try imageOnly.validate(.textCapabilities) }
    }

    @Test func aByteLimitMustBePositive() throws {
        let rig = try ValidatorRig()
        for limit: Int64 in [0, -1] {
            guard case .internalInvariant = rig.refusal(.execute(rig.job, try rig.plan(), outputByteLimit: limit))
            else {
                Issue.record("limit \(limit) passed")
                continue
            }
        }
    }

    @Test func aWorkspaceForAnotherJobIsRefused() throws {
        let rig = try ValidatorRig()
        guard case .prepare(let request, let workspace) = try rig.prepare() else { return }
        let other = WorkerRequest.prepare(request, JobWorkspace(job: JobID(), stagedFile: workspace.stagedFile))
        guard case .internalInvariant = rig.refusal(other) else {
            Issue.record("a workspace of another job passed")
            return
        }
    }
}
