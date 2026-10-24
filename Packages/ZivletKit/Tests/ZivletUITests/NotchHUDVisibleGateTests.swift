import Foundation
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

/// G-M5a-1 (19b §6.2): a progress snapshot that draws nothing new stops before the board, so it neither publishes,
/// nor reaches the host, nor refreshes the spoken value. Finishing and the next visible step always get through.
@Suite("Notch HUD drops snapshots that draw nothing new (G-M5a-1)")
@MainActor
struct NotchHUDVisibleGateTests {
    private static func progress(_ fraction: Double) -> JobProgress {
        JobProgress(fraction: fraction, eta: .seconds(40))
    }

    @Test func snapshotsThatDrawNothingNewNeitherPublishNorReachTheHost() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var transitions = 0
        rig.hud.onApply = { transitions += 1 }
        let first = try HUDFx.running(Self.progress(0.40))
        rig.hud.prepare(near: NotchRig.onNotch)
        rig.hud.show(first)
        let before = transitions
        for step in 1...4 {
            await rig.clock.advance(by: .milliseconds(100))
            rig.hud.show(first.applyingProgress(Self.progress(0.40 + Double(step) * 0.001)))
        }
        #expect(transitions == before)
    }

    @Test func theNextVisibleStepStillRedrawsWithin250ms() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var transitions = 0
        rig.hud.onApply = { transitions += 1 }
        let first = try HUDFx.running(Self.progress(0.40))
        rig.hud.show(first)
        let spokenBefore = rig.hosts.host(on: 1)?.accessibilityValue
        let before = transitions
        await rig.clock.advance(by: .milliseconds(250))
        rig.hud.show(first.applyingProgress(Self.progress(0.41)))
        #expect(transitions == before + 1)
        #expect(Self.publishedFraction(rig, first.batch) == 0.41)
        #expect(rig.hosts.host(on: 1)?.accessibilityValue != spokenBefore)
    }

    @Test func aStepThatCameTooSoonIsDrawnByTheNextSnapshot() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let first = try HUDFx.running(Self.progress(0.40))
        rig.hud.show(first)
        await rig.clock.advance(by: .milliseconds(100))
        rig.hud.show(first.applyingProgress(Self.progress(0.41)))
        #expect(Self.publishedFraction(rig, first.batch) == 0.40)
        await rig.clock.advance(by: .milliseconds(200))
        rig.hud.show(first.applyingProgress(Self.progress(0.412)))
        #expect(Self.publishedFraction(rig, first.batch) == 0.412)
    }

    @Test func aFinishedSnapshotIsNeverDropped() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let running = try HUDFx.running(Self.progress(0.999))
        rig.hud.show(running)
        let job = try #require(running.items.first?.job)
        let output = PublishedOutput(
            url: URL(filePath: "/tmp/clip.mp4"), format: .mp4, byteCount: 1, fileID: 1, modified: .distantPast)
        let finished = running.applying(.changed(running.batch, job, .succeeded(output)))
            .applying(.finished(running.batch))
        rig.hud.show(finished)
        #expect(rig.hud.board.item(.batch(running.batch))?.snapshot?.isFinished == true)
        #expect(rig.hosts.surface(on: 1) == .toast)
    }

    private static func publishedFraction(_ rig: NotchRig, _ batch: BatchID) -> Double? {
        rig.hud.model.board.item(.batch(batch))?.snapshot?.currentProgress?.fraction
    }
}
