import AppKit
import NotchTestSupport
import TestSupport
import Testing
import ZivletActions
import ZivletNotch
import ZivletNotchCore
import ZivletShelfCore
import ZivletTrigger

@testable import ZivletBox

/// Records the sides Quick Look was asked for, answering each at once with a small image.
@MainActor
final class RecordingThumbnailMaker: ThumbnailMaking {
    private(set) var sides: [Double] = []

    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? {
        sides.append(side)
        return GatedThumbnailMaker.image
    }
}

/// The tray over a real controller in a fresh session (the panel never shown): the review found its strip could not
/// be dragged, showed no badges and never asked for its own thumbnails.
@Suite("The tray over a real box (P2-143)")
@MainActor
struct TrayRealBoxTests {
    /// A box saved by one launch, then a fresh launch whose panel stays hidden.
    static func freshLaunch(_ rig: BoxRig, files: Int) async throws -> BoxController {
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(files), newBox: false)
        first.quit()
        let again = rig.controller()
        again.start()
        return again
    }

    /// The compact view opens on the notch display, as a hover would open it.
    static func expand(_ rig: TrayRig) async {
        rig.hosts.request(
            IslandRequest(client: .tray, display: 1, resting: .expanded, hoverSurface: .expanded), from: .tray)
        rig.hosts.contentChanged(on: 1)
        await settle()
    }

    @Test func theRestingTrayResolvesNothing() async throws {
        let rig = try BoxRig()
        let box = try await Self.freshLaunch(rig, files: 3)
        let before = rig.bookmarks.resolveCalls
        let tray = try TrayRig(box: box)
        tray.tray.boxChanged()
        await settle()
        #expect(tray.hosts.surface(on: 1) == .sensor && rig.bookmarks.resolveCalls == before)
    }

    @Test func openingTheCompactViewResolvesTheBoxSoItsStripCanBeDragged() async throws {
        let rig = try BoxRig()
        let box = try await Self.freshLaunch(rig, files: 3)
        #expect(box.trayModel.items.allSatisfy { $0.url == nil })
        let tray = try TrayRig(box: box)
        await Self.expand(tray)
        #expect(box.trayModel.items.allSatisfy { $0.url != nil })
        #expect(box.trayModel.items.map(\.url?.lastPathComponent) == ["f0.txt", "f1.txt", "f2.txt"])
        #expect(!box.panel.isVisible)
    }

    @Test func aMissingItemShowsItsBadgeInTheTray() async throws {
        let rig = try BoxRig()
        let box = try await Self.freshLaunch(rig, files: 2)
        let gone = try #require(box.current?.items.first?.lastKnownPath)
        rig.bookmarks.resolutions[gone] = .failed(code: 4, storedVolumePath: "/", storedVolumeName: "Disk")
        let tray = try TrayRig(box: box)
        await Self.expand(tray)
        #expect(box.trayModel.items.first?.badge == BoxSymbols.badgeMissing)
    }

    @Test func theStripAsksForTrayThumbnails() async throws {
        let rig = try BoxRig()
        let maker = RecordingThumbnailMaker()
        rig.thumbnailMaker = maker
        let box = try await Self.freshLaunch(rig, files: 2)
        let tray = try TrayRig(box: box)
        await Self.expand(tray)
        #expect(maker.sides == [Double(BoxLook.Tray.thumb), Double(BoxLook.Tray.thumb)])
        let first = try #require(box.current?.items.first?.id)
        #expect(box.trayModel.images[first]?.size.width == BoxLook.Tray.thumb)
    }

    @Test func aDropOfWhatIsAlreadyThereSaysSoAndIsNotAFailure() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        let tray = try TrayRig(box: box)
        tray.holdsLingers = true
        tray.tray.proximity(.entered(display: 1), itemCount: 2)
        let board = TestPasteboard(urls: files)
        #expect(tray.tray.performDrop(FakeDraggingInfo(pasteboard: board.board), display: 1))
        await tray.tray.dropTask?.value
        #expect(tray.tray.lastToast?.text == "Already in the box" && tray.tray.lastToast?.failed == false)
        #expect(rig.results.results.isEmpty)
        tray.releaseLingers()
        withExtendedLifetime(board) {}
    }

    @Test func aPartlyAddedDropShowsTheToastAndTheCardOfWhatWasLeftOut() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add([files[0]], newBox: false)
        let tray = try TrayRig(box: box)
        tray.holdsLingers = true
        tray.tray.proximity(.entered(display: 1), itemCount: 2)
        let board = TestPasteboard(urls: files)
        _ = tray.tray.performDrop(FakeDraggingInfo(pasteboard: board.board), display: 1)
        await tray.tray.dropTask?.value
        #expect(tray.tray.lastToast?.text == "Added 1")
        #expect(rig.results.results.last?.card?.lines == ["f0.txt is already in the box."])
        tray.releaseLingers()
        withExtendedLifetime(board) {}
    }

    @Test func theCompactViewPreparesOnceEachTimeItOpens() async throws {
        let rig = try TrayRig(boxItems: 3)
        #expect(rig.tray.accessibilityValue(display: 1) == BoxSpeech.header(count: 3, bytes: 3_000_000))
        #expect(rig.box.prepared == 0)
        await Self.expand(rig)
        _ = rig.tray.content(for: .expanded, display: 1)
        #expect(rig.box.prepared == 1)
        rig.tray.surfaceChanged(.sensor, display: 1)
        _ = rig.tray.content(for: .expanded, display: 1)
        #expect(rig.box.prepared == 2)
    }
}
