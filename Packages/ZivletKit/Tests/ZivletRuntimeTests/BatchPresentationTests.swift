import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

@Suite("HUD wording from batch snapshots, and wheel capability targets")
struct BatchPresentationTests {
    static let output = PublishedOutput(
        url: URL(fileURLWithPath: "/x/Sunset.png"), format: .png, byteCount: 2_048, fileID: 1, modified: .distantPast)

    static func snapshot(_ states: [JobState], notes: [PlanNote] = [], finished: Bool = true) -> BatchSnapshot {
        let items = states.enumerated().map { index, state in
            BatchItem(job: JobID(), name: "file\(index).jpg", state: state, notes: index == 0 ? notes : [])
        }
        return BatchSnapshot(batch: BatchID(), target: .png, items: items, isFinished: finished)
    }

    @Test func workingShowsTheTargetTheItemAndThePercentage() {
        let shown = BatchPresentation.make(
            Self.snapshot([.succeeded(Self.output), .running(JobProgress(fraction: 0.5))], finished: false))
        #expect(shown.phase == .working && shown.title == "Converting to PNG")
        #expect(shown.subtitle == "file1.jpg · 2 of 2 · 75%" && shown.fraction == 0.75 && shown.canCancel)
    }

    @Test func oneSavedFileIsNamedWithItsNotes() {
        let shown = BatchPresentation.make(Self.snapshot([.succeeded(Self.output)], notes: [.alphaFlattened]))
        #expect(shown.phase == .succeeded && shown.title == "Saved Sunset.png" && shown.subtitle == "PNG · 2 KB")
        #expect(shown.notes == ["Transparency was flattened onto white."] && shown.canUndo && shown.canReveal)
        #expect(!shown.canCancel && shown.fraction == nil)
    }

    @Test func severalSavedFilesAreCounted() {
        let shown = BatchPresentation.make(
            Self.snapshot([.succeeded(Self.output), .succeeded(Self.output)], notes: [.firstFrameOnly]))
        #expect(shown.title == "Saved 2 files" && shown.notes == ["Only the first frame or page was kept."])
    }

    @Test func anSVGSavedAsPDFSaysItIsAPicture() {
        let shown = BatchPresentation.make(Self.snapshot([.succeeded(Self.output)], notes: [.svgRasterizedInPDF]))
        #expect(shown.notes == ["The drawing was saved as a picture inside the PDF."])
    }

    @Test func partialSuccessNamesTheFirstFailure() {
        let shown = BatchPresentation.make(Self.snapshot([.succeeded(Self.output), .failed(.diskFull)]))
        #expect(shown.phase == .partial && shown.title == "Saved 1 of 2 files")
        #expect(shown.subtitle == "file1.jpg: There isn't enough free disk space.")
    }

    @Test func aSingleFailureLeadsWithItsCopyAndDetail() {
        let shown = BatchPresentation.make(Self.snapshot([.failed(.routeUnavailable(.mp3, .ogg, ["libvorbis"]))]))
        #expect(shown.phase == .failed && shown.title == "Converting to OGG isn't available on this Mac yet.")
        #expect(shown.subtitle == "file0.jpg" && shown.detail == "Missing: libvorbis." && !shown.canUndo)
        let many = BatchPresentation.make(Self.snapshot([.failed(.diskFull), .failed(.cancelled)]))
        #expect(many.title == "None of the 2 files could be converted")
    }

    @Test func cancelledBatchesSayWhatHappened() {
        let snapshot = Self.snapshot([.cancelled])
        #expect(BatchPresentation.make(snapshot).phase == .cancelled)
        #expect(BatchPresentation.logLine(snapshot) == "0 saved, 0 failed, 1 cancelled")
    }

    @Test func unavailableTargetsComeFromTheEngines() async {
        let blocked = FakeEngine(availability: .unavailable(["x"]))
        let scheduler = JobScheduler(engines: [blocked], records: nil)
        let none = await ConversionService(scheduler: scheduler, engines: [blocked]).unavailableTargets()
        #expect(none == ConversionCatalog.standard.distinctTargets)
        let open = await ConversionService(scheduler: scheduler, engines: [FakeEngine()]).unavailableTargets()
        #expect(open.isEmpty)
        let partial = await ConversionService(scheduler: scheduler, engines: []).unavailableTargets()
        #expect(partial == ConversionCatalog.standard.distinctTargets)
    }
}
