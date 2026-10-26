import Darwin
import Dispatch
import EngineImage
import Foundation
import ZivletIPC
import ZivletWorkerCore
import os

// ZivletWorker (P2-01, 02 §2.1): an unsandboxed XPC service with the hardened runtime and no entitlements, started
// by launchd at the app's first job. It hosts the image engine behind WorkerService, accepts only the app (D-M6-7),
// and exits 60 s after its last request (D-M6-10).

let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")

// ImageIO and the text engines read UTF-8 file names (05 §9.1 P2-19 note).
setlocale(LC_CTYPE, "UTF-8")

/// The DEBUG smoke run's real crash (D-M6-18): SIGKILL writes no crash report.
@Sendable func selfKill(afterMilliseconds milliseconds: Int) {
    #if DEBUG
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(max(0, milliseconds))) {
            kill(getpid(), SIGKILL)
        }
    #endif
}

let service = WorkerService(
    engines: [ImageEngine()],
    onIdle: {
        logger.notice("Worker idle; exiting")
        exit(0)
    }, onSelfKill: selfKill(afterMilliseconds:))

let requirement = WorkerPeerPolicy.requirement(own: .current(), peer: WorkerPeerPolicy.appIdentifier)
let listener: AnyObject
do {
    listener = try WorkerXPCHost.listen(service: service, requirement: requirement)
} catch {
    logger.error("Worker listener did not start: \(String(describing: error), privacy: .private)")
    exit(1)
}
logger.notice("Worker started: pid \(getpid(), privacy: .public)")
withExtendedLifetime(listener) { dispatchMain() }
