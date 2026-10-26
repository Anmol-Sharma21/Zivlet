import AppKit
import TestSupport
import Testing

@testable import ZivletBox

/// A thumbnail maker whose requests wait until the test lets them finish; a cancelled request ends at once.
@MainActor
final class GatedThumbnailMaker: ThumbnailMaking {
    private(set) var requests: [URL] = []
    private(set) var cancelled = 0
    private var gates: [URL: CheckedContinuation<CGImage?, Never>] = [:]
    /// Finished before their request arrived (a busy main actor): the request returns at once, so no wait is lost.
    private var early: Set<URL> = []

    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? {
        requests.append(url)
        if early.remove(url) != nil { return Self.image }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { gates[url] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel(url) }
        }
    }

    func finish(_ url: URL) {
        guard let gate = gates.removeValue(forKey: url) else {
            early.insert(url)
            return
        }
        gate.resume(returning: Self.image)
    }

    private func cancel(_ url: URL) {
        guard let gate = gates.removeValue(forKey: url) else { return }
        cancelled += 1
        gate.resume(returning: nil)
    }

    static let image: CGImage? = {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }()
}

/// A maker that fails the test when called: the placeholder path must not read files.
@MainActor
final class FailingThumbnailMaker: ThumbnailMaking {
    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? {
        Issue.record("the placeholder path asked for a thumbnail")
        return nil
    }
}

@MainActor
/// Lets the tasks the test started run: yields, then a short sleep, since parallel suites share the main actor.
func settle() async {
    for _ in 0..<50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
}

@Suite("Thumbnail cache (D-M5b-14, 19c D-BL11)")
@MainActor
struct ThumbnailCacheTests {
    private func url(_ n: Int) -> URL { URL(filePath: "/tmp/box-thumb-\(n).png") }

    @Test func aFifthRequestWaitsUntilOneOfFourFinishes() async {
        let maker = GatedThumbnailMaker()
        let cache = ThumbnailCache(maker: maker)
        let ids = (0..<5).map { _ in UUID() }
        cache.setVisible(Set(ids))
        let tasks = ids.enumerated().map { n, id in Task { await cache.thumbnail(for: id, url: url(n), size: .cell) } }
        await settle()
        #expect(maker.requests.count == 4)
        maker.finish(url(0))
        await settle()
        #expect(maker.requests.count == 5)
        for n in 1..<5 { maker.finish(url(n)) }
        for task in tasks { #expect(await task.value != nil) }
    }

    @Test func anItemThatScrollsOutIsCancelled() async {
        let maker = GatedThumbnailMaker()
        let cache = ThumbnailCache(maker: maker)
        let id = UUID()
        cache.setVisible([id])
        let task = Task { await cache.thumbnail(for: id, url: url(1), size: .cell) }
        await settle()
        cache.setVisible([])
        #expect(await task.value == nil)
        #expect(maker.cancelled == 1)
    }

    @Test func aWaitingItemThatScrollsOutNeverAsks() async {
        let maker = GatedThumbnailMaker()
        let cache = ThumbnailCache(maker: maker, maxConcurrent: 1)
        let (first, second) = (UUID(), UUID())
        cache.setVisible([first, second])
        let running = Task { await cache.thumbnail(for: first, url: url(1), size: .cell) }
        let waiting = Task { await cache.thumbnail(for: second, url: url(2), size: .cell) }
        await settle()
        cache.setVisible([first])
        #expect(await waiting.value == nil)
        maker.finish(url(1))
        #expect(await running.value != nil)
        #expect(maker.requests == [url(1)])
    }

    @Test func anItemThatIsNotVisibleIsNotAskedFor() async {
        let maker = GatedThumbnailMaker()
        let cache = ThumbnailCache(maker: maker)
        #expect(await cache.thumbnail(for: UUID(), url: url(1), size: .cell) == nil)
        #expect(maker.requests.isEmpty)
    }

    @Test func aSecondRequestHitsTheCache() async {
        let maker = GatedThumbnailMaker()
        let cache = ThumbnailCache(maker: maker)
        let id = UUID()
        cache.setVisible([id])
        let first = Task { await cache.thumbnail(for: id, url: url(1), size: .cell) }
        await settle()
        maker.finish(url(1))
        #expect(await first.value != nil)
        #expect(cache.cached(id, size: .cell) != nil && cache.cached(id, size: .tray) == nil)
        #expect(await cache.thumbnail(for: id, url: url(1), size: .cell) != nil)
        #expect(maker.requests.count == 1)
    }

    @Test func thePlaceholderIsTheTypeIconWithoutReadingTheFile() {
        let cache = ThumbnailCache(maker: FailingThumbnailMaker())
        let image = cache.placeholder(forName: "photo.heic")
        #expect(image.size.width > 0)
        #expect(cache.placeholder(forName: "photo.heic") === image)
        #expect(cache.placeholder(forName: "no-extension").size.width > 0)
    }

    @Test func sizesFollowTheTokens() {
        #expect(ThumbnailSize.cell.side == Double(BoxLook.Grid.thumb))
        #expect(ThumbnailSize.tray.side == Double(BoxLook.Tray.thumb))
    }
}

@Suite("Quick Look thumbnail maker (19c D-BL11)")
@MainActor
struct SystemThumbnailMakerTests {
    @Test func aTextFileGetsAThumbnailOrNilWithoutThrowing() async throws {
        let dir = try TempDir()
        let file = try dir.file("note.txt", "Zivlet box thumbnail test")
        let image = await SystemThumbnailMaker().thumbnail(for: file, side: 48, scale: 2)
        if let image { #expect(image.width > 0) }
    }

    @Test func aMissingFileGivesNil() async {
        let missing = URL(filePath: "/nonexistent-zivlet-\(UUID().uuidString).png")
        #expect(await SystemThumbnailMaker().thumbnail(for: missing, side: 48, scale: 2) == nil)
    }
    /// Plain text keeps its type icon (owner, 2026-10-26): Quick Look's white page was the brightest thing on the glass.
    @Test(arguments: ["notes.txt", "README.md", "data.csv", "main.swift"])
    func plainTextKeepsItsTypeIcon(name: String) async {
        let cache = ThumbnailCache(maker: FailingThumbnailMaker())
        let id = UUID()
        cache.setVisible([id])
        #expect(await cache.thumbnail(for: id, url: URL(filePath: "/tmp/\(name)"), size: .cell) == nil)
    }

    @Test func imagesStillAskQuickLook() async {
        let maker = GatedThumbnailMaker()
        let cache = ThumbnailCache(maker: maker)
        let id = UUID()
        cache.setVisible([id])
        let task = Task { await cache.thumbnail(for: id, url: URL(filePath: "/tmp/box-thumb-7.png"), size: .cell) }
        await settle()
        #expect(maker.requests == [URL(filePath: "/tmp/box-thumb-7.png")])
        maker.finish(URL(filePath: "/tmp/box-thumb-7.png"))
        #expect(await task.value != nil)
    }
}
