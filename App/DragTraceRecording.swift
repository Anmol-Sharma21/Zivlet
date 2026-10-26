#if DEBUG
    import Foundation
    import ZivletCore
    import ZivletNotch
    import ZivletNotchCore
    import ZivletTrigger
    import ZivletTriggerHost
    import os

    /// Debug builds only (D-M5b-10, `docs/plan/qa/drop-box.md` §R): launched with `-ZivletRecordDragTraces
    /// normal|notch`, every file drag the trigger host watches is saved as a drag trace in
    /// `~/Library/Application Support/Zivlet/DragTraces/` for `make drag-replay TRACES=<folder>`. Without the flag
    /// nothing is recorded. It rides on the host's live samples, so Pause stops it too.
    enum DragTraceRecording {
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "trigger")

        static func start(trigger: TriggerHost, displays: ScreenGeometryReader) -> DragTraceRecorder? {
            guard let value = DragTraceRecorder.launchValue(in: CommandLine.arguments) else { return nil }
            guard let label = DragTraceRecorder.label(fromLaunchValue: value) else {
                logger.error("DragTrace: unknown value for -ZivletRecordDragTraces; not recording")
                return nil
            }
            let folder: URL
            do {
                folder = try DragTraceRecorder.standardFolder()
            } catch {
                logger.error("DragTrace: no Application Support folder; not recording")
                return nil
            }
            let recorder = DragTraceRecorder(
                folder: folder, label: label,
                display: { [weak displays] point in
                    IslandLayout.display(for: point, in: displays?.displays ?? []).map(TraceDisplay.init)
                },
                log: { logger.notice("\($0, privacy: .public)") })
            let previousSample = trigger.onLiveSample
            trigger.onLiveSample = { sample in
                previousSample(sample)
                recorder.observe(sample)
            }
            let previousEnd = trigger.onDragEnded
            trigger.onDragEnded = {
                previousEnd()
                recorder.dragEnded()
            }
            logger.notice("DragTrace: recording \(label.rawValue, privacy: .public)")
            return recorder
        }
    }

    extension TraceDisplay {
        init(_ display: DisplayGeometry) {
            self.init(
                id: display.id, frame: display.frame, visibleFrame: display.visibleFrame,
                safeAreaTop: display.safeAreaTop, auxiliaryTopLeft: display.auxiliaryTopLeft,
                auxiliaryTopRight: display.auxiliaryTopRight)
        }
    }
#endif
