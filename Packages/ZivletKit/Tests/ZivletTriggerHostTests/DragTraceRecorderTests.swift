#if DEBUG
    import Foundation
    import TestSupport
    import Testing
    import ZivletCore
    import ZivletTrigger

    @testable import ZivletTriggerHost

    @Suite("Drag-trace recorder (Debug only, D-M5b-10)")
    @MainActor
    struct DragTraceRecorderTests {
        static let display = TraceDisplay(
            id: 1, frame: Rect2D(x: 0, y: 0, width: 1800, height: 1169),
            visibleFrame: Rect2D(x: 0, y: 94, width: 1800, height: 1036), safeAreaTop: 38,
            auxiliaryTopLeft: Rect2D(x: 0, y: 1131, width: 790, height: 38),
            auxiliaryTopRight: Rect2D(x: 1010, y: 1131, width: 790, height: 38))

        private final class Log {
            var lines: [String] = []
        }

        private func recorder(
            in dir: TempDir, label: DragTrace.Label = .notch, display: TraceDisplay? = display, log: Log = Log()
        ) -> DragTraceRecorder {
            DragTraceRecorder(
                folder: dir.url.appending(path: "DragTraces"), label: label, display: { _ in display },
                os: "27.0", now: { Date(timeIntervalSince1970: 1_800_000_000) }, log: { log.lines.append($0) })
        }

        private func sample(_ index: Int, x: Double = 900, y: Double = 1150) -> InputSample {
            InputSample(
                uptime: .seconds(1) + .milliseconds(8 * index), source: .frame, primaryButtonDown: true,
                dragChangeCount: 1, dragHasFileTypes: true, location: Point2D(x: x, y: y))
        }

        @Test func oneDragWritesOnePrivateValidTrace() throws {
            let dir = try TempDir()
            let log = Log()
            let recorder = recorder(in: dir, log: log)
            for index in 0..<25 { recorder.observe(sample(index)) }
            let file = try #require(recorder.dragEnded())
            let folderMode =
                try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[
                    .posixPermissions] as? Int
            let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            #expect(folderMode == 0o700 && fileMode == 0o600)
            let trace = try JSONDecoder().decode(DragTrace.self, from: Data(contentsOf: file))
            #expect(trace.label == .notch && trace.samples.count == 25 && trace.display == Self.display)
            #expect(trace.samples.first == DragTrace.Sample(t: 1_000, x: 900, y: 1150, down: true))
            #expect(file.lastPathComponent.hasSuffix("-notch-1.json"))
            #expect(log.lines == ["DragTrace: saved 25 samples"])
        }

        @Test func eachDragGetsItsOwnFile() throws {
            let dir = try TempDir()
            let recorder = recorder(in: dir, label: .normal)
            for index in 0..<5 { recorder.observe(sample(index)) }
            let first = try #require(recorder.dragEnded())
            for index in 10..<15 { recorder.observe(sample(index)) }
            let second = try #require(recorder.dragEnded())
            #expect(first != second && second.lastPathComponent.hasSuffix("-normal-2.json"))
        }

        @Test func aDragLongerThanTheCapIsNotSaved() throws {
            let dir = try TempDir()
            let log = Log()
            let recorder = recorder(in: dir, log: log)
            for index in 0...DragTraceRecorder.sampleCap { recorder.observe(sample(index)) }
            #expect(recorder.sampleCount == DragTraceRecorder.sampleCap)
            #expect(recorder.dragEnded() == nil)
            #expect(log.lines == ["DragTrace: not saved (over 20000 samples)"])
            #expect(recorder.sampleCount == 0)
        }

        @Test func aDragWithoutSamplesWritesNothing() throws {
            let dir = try TempDir()
            let log = Log()
            #expect(recorder(in: dir, log: log).dragEnded() == nil)
            #expect(log.lines.isEmpty)
        }

        @Test func aDragWithNoDisplayUnderItIsNotSaved() throws {
            let dir = try TempDir()
            let log = Log()
            let recorder = recorder(in: dir, display: nil, log: log)
            for index in 0..<5 { recorder.observe(sample(index)) }
            #expect(recorder.dragEnded() == nil)
            #expect(log.lines == ["DragTrace: not saved (no display under the drag)"])
        }

        @Test func anInvalidDragIsNotSavedAndSaysWhy() throws {
            let dir = try TempDir()
            let log = Log()
            let recorder = recorder(in: dir, log: log)
            recorder.observe(sample(0))
            #expect(recorder.dragEnded() == nil)
            #expect(log.lines == ["DragTrace: not saved (\(DragTraceError.sampleCount(1).description))"])
        }

        @Test func aFullFolderStopsTheRecorderAndSaysSoOnce() throws {
            let dir = try TempDir()
            let log = Log()
            let recorder = DragTraceRecorder(
                folder: dir.url.appending(path: "DragTraces"), label: .notch, display: { _ in Self.display },
                os: "27.0", fileCap: 2, now: { Date(timeIntervalSince1970: 1_800_000_000) },
                log: { log.lines.append($0) })
            for drag in 0..<4 {
                for index in 0..<3 { recorder.observe(sample(drag * 10 + index)) }
                recorder.dragEnded()
            }
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.url.appending(path: "DragTraces").path)
            #expect(files.count == 2)
            #expect(log.lines.filter { $0.hasPrefix("DragTrace: folder full") }.count == 1)
        }

        @Test func theLaunchFlagPicksTheLabelAndNothingElseStartsIt() {
            #expect(DragTraceRecorder.label(fromLaunchValue: "notch") == .notch)
            #expect(DragTraceRecorder.label(fromLaunchValue: "normal") == .normal)
            #expect(DragTraceRecorder.label(fromLaunchValue: nil) == nil)
            #expect(DragTraceRecorder.label(fromLaunchValue: "yes") == nil)
            #expect(DragTraceRecorder.launchValue(in: ["Zivlet", "-ZivletRecordDragTraces", "notch"]) == "notch")
            #expect(DragTraceRecorder.launchValue(in: ["Zivlet", "-ZivletRecordDragTraces"]) == nil)
            #expect(DragTraceRecorder.launchValue(in: ["Zivlet"]) == nil)
        }

        @Test func theStandardFolderIsInApplicationSupport() throws {
            let folder = try DragTraceRecorder.standardFolder()
            #expect(folder.path.hasSuffix("Application Support/Zivlet/DragTraces"))
        }
    }
#endif
