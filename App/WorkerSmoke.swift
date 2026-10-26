#if DEBUG
    import CoreGraphics
    import Darwin
    import Foundation
    import ImageIO
    import ZivletCore
    import ZivletEngineKit
    import ZivletIPC
    import ZivletRuntime
    import EngineImage

    /// DEBUG: `-ZivletWorkerSmoke <folder> [-ZivletWorkerIdleSeconds <n>]` (plan 18c C12, exit row Z5). Without UI,
    /// runs the real worker through convert, cancel, one crash, two crashes and the idle exit, writing one JSON line
    /// per step to `<folder>/worker-smoke.jsonl`; `Scripts/worker-smoke.sh` reads them. Files are written only into
    /// `<folder>`. The crashes are the worker's own SIGKILL (no crash report, D-M6-18).
    struct WorkerSmoke {
        static let folderFlag = "-ZivletWorkerSmoke"
        static let idleFlag = "-ZivletWorkerIdleSeconds"

        let folder: URL
        let idleSeconds: Int
        let selection = WorkerSelection.standard()
        let log: SmokeLog

        /// Nil without the flag; the folder must be an existing absolute directory.
        static func parse(arguments: [String]) -> WorkerSmoke? {
            guard let index = arguments.firstIndex(of: folderFlag), index + 1 < arguments.count else { return nil }
            let path = arguments[index + 1]
            var isFolder: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder),
                isFolder.boolValue
            else { return nil }
            let idle =
                arguments.firstIndex(of: idleFlag).flatMap { arguments.indices.contains($0 + 1) ? $0 + 1 : nil }
                .flatMap { Int(arguments[$0]) } ?? 5
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            return WorkerSmoke(
                folder: folder, idleSeconds: max(1, idle),
                log: SmokeLog(file: folder.appending(path: "worker-smoke.jsonl")))
        }

        func run() async {
            guard await checkWorker() else { return log.write("done", ok: false, ms: 0, "no worker") }
            let small = SmokeFixtures.png(in: folder)
            let slow = SmokeFixtures.noiseTIFF(in: folder)
            await convert(small)
            await cancel(slow)
            await crashOnce(slow)
            await crashTwice(slow, then: small)
            await idleExit()
            log.write("done", ok: true, ms: 0, "")
        }

        private var connection: WorkerConnection { selection.workerConnection }

        private func checkWorker() async -> Bool {
            let clock = SmokeClock()
            guard case .worker = await selection.choice(), case .running(let pid) = await selection.status else {
                log.write("worker", ok: false, ms: clock.ms, await selection.status.line)
                return false
            }
            log.write("worker", ok: pid != getpid(), ms: clock.ms, "pid \(pid), app pid \(getpid())")
            return pid != getpid()
        }

        private func convert(_ input: URL?) async {
            let clock = SmokeClock()
            let states = await SmokeBatch(folder: folder, selection: selection).run([(input, .png, .jpg)]) { _ in }
            let ok = states.first?.published != nil
            log.write("convert", ok: ok, ms: clock.ms, ok ? "PNG to JPEG in the worker" : SmokeLog.describe(states))
        }

        private func cancel(_ input: URL?) async {
            let clock = SmokeClock()
            let marks = SmokeMarks()
            let batch = SmokeBatch(folder: folder, selection: selection)
            let states = await batch.run([(input, .tiff, .png)]) { event in
                if case .running = event.state, marks.once("running") {
                    try? await Task.sleep(for: .milliseconds(200))
                    marks.stamp("cancel")
                    await batch.scheduler.cancel(job: event.job)
                }
                if event.state == .cancelled { marks.stamp("cancelled") }
            }
            let visible = marks.between("cancel", "cancelled")
            let ok = states.first == .cancelled && visible <= 100
            log.write("cancel", ok: ok, ms: clock.ms, "visible in \(visible) ms, worker stopped by \(clock.ms) ms")
        }

        private func crashOnce(_ input: URL?) async {
            let clock = SmokeClock()
            let marks = SmokeMarks()
            let states = await SmokeBatch(folder: folder, selection: selection).run([(input, .tiff, .png)]) { event in
                if case .running = event.state, marks.once("kill") { await kill(marks) }
                if event.state == .retrying { marks.stamp("retrying") }
                if case .running = event.state, marks.has("retrying"), marks.once("back") { marks.stamp("back") }
            }
            let ok = states.first?.published != nil && marks.has("retrying")
            log.write(
                "crash-retry", ok: ok, ms: clock.ms,
                "relaunch \(marks.between("kill", "back")) ms, \(SmokeLog.describe(states))")
        }

        private func crashTwice(_ input: URL?, then next: URL?) async {
            let clock = SmokeClock()
            let marks = SmokeMarks()
            let batch = [(input, FormatID.tiff, FormatID.png), (next, .png, .tiff)]
            let states = await SmokeBatch(folder: folder, selection: selection).run(batch) { event in
                guard event.index == 0 else { return }
                if event.state == .retrying { marks.stamp("retrying1") }
                guard case .running = event.state else { return }
                if marks.once("kill1") || (marks.has("retrying1") && marks.once("kill2")) { await kill(marks) }
            }
            let ok = states.first == .failed(.engineCrashedOnInput) && states.last?.published != nil
            let copy = JobErrorCopy.copy(for: .engineCrashedOnInput).message
            log.write(
                "crash-twice", ok: ok, ms: clock.ms, ok ? "\(copy) The next job was saved." : SmokeLog.describe(states))
        }

        private func kill(_ marks: SmokeMarks) async {
            try? await Task.sleep(for: .milliseconds(50))
            marks.stamp("kill")
            _ = try? await connection.send(.selfKillForTesting(afterMilliseconds: 20))
        }

        private func idleExit() async {
            guard let pong = try? await connection.ping() else {
                return log.write("idle-exit", ok: false, ms: 0, "no worker answered")
            }
            _ = try? await connection.send(.setIdleForTesting(seconds: idleSeconds))
            let clock = SmokeClock()
            let limit = (idleSeconds + 15) * 1000
            while Darwin.kill(pong.pid, 0) == 0, clock.ms < limit { try? await Task.sleep(for: .milliseconds(100)) }
            let gone = Darwin.kill(pong.pid, 0) != 0
            log.write("idle-exit", ok: gone, ms: clock.ms, "pid \(pong.pid) \(gone ? "gone" : "still running")")
        }
    }
#endif
