import AppKit
import NotchTestSupport
import SwiftUI
import Testing
import ZivletNotchCore

@testable import ZivletNotch

/// A tray-like client that takes drops and records what reached it.
@MainActor
final class FakeDropClient: IslandClient, IslandDropHandling {
    let dragTypes: [NSPasteboard.PasteboardType]
    private(set) var entered: [UInt32] = []
    private(set) var updated: [UInt32] = []
    private(set) var exited: [UInt32] = []
    private(set) var dropped: [(display: UInt32, items: Int)] = []

    init(types: [NSPasteboard.PasteboardType] = [.fileURL]) { dragTypes = types }

    func content(for surface: IslandSurface, display: UInt32) -> AnyView { AnyView(Text("Add")) }
    func accessibilityLabel(display: UInt32) -> String { "Drop Box" }
    func accessibilityValue(display: UInt32) -> String { "" }
    var accessibilityActionName: String { "Open Drop Box" }
    func accessibilityActionPerformed(display: UInt32) {}
    func held(_ held: Bool, display: UInt32, now: Duration) {}
    func closeRequested(display: UInt32) {}
    func displaysChanged(_ ids: [UInt32], replacing: [UInt32: UInt32]) {}

    func draggingEntered(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation {
        entered.append(display)
        return .copy
    }

    func draggingUpdated(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation {
        updated.append(display)
        return .copy
    }

    func draggingExited(display: UInt32) { exited.append(display) }

    func performDrop(_ info: any NSDraggingInfo, display: UInt32) -> Bool {
        dropped.append((display, info.draggingPasteboard.pasteboardItems?.count ?? 0))
        return true
    }
}

@Suite("Island drop plumbing (D-M5b-7, D-M5b-8)")
@MainActor
struct IslandDropTests {
    static let drop = IslandRequest(client: .tray, display: 1, resting: .dropTarget, hoverSurface: .dropTarget)
    static let sensor = IslandRequest(client: .tray, display: 1, resting: .sensor, hoverSurface: .expanded)

    private func rig() throws -> (IslandHosts, FakeDropClient) {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchOnly(), clock: ManualClock(), animation: .instant)
        let tray = FakeDropClient()
        hosts.register(tray, as: .tray)
        return (hosts, tray)
    }

    private func registered(_ hosts: IslandHosts, on display: UInt32 = 1) -> [NSPasteboard.PasteboardType] {
        hosts.host(on: display)?.tracking.registeredDraggedTypes ?? []
    }

    @Test func dragTypesAreRegisteredOnlyWhileTheTrayAsks() throws {
        let (hosts, _) = try rig()
        #expect(registered(hosts).isEmpty)
        hosts.request(Self.sensor, from: .tray)
        #expect(registered(hosts).isEmpty)
        hosts.request(Self.drop, from: .tray)
        #expect(registered(hosts) == [.fileURL])
        hosts.request(Self.sensor, from: .tray)
        #expect(registered(hosts).isEmpty)
        hosts.request(Self.drop, from: .tray)
        hosts.request(nil, from: .tray)
        #expect(registered(hosts).isEmpty)
        hosts.close()
    }

    @Test func theWheelUnregistersAtOnceEvenWhileTheRequestStillAsks() throws {
        let (hosts, _) = try rig()
        hosts.request(Self.drop, from: .tray)
        hosts.wheelShown()
        #expect(registered(hosts).isEmpty)
        #expect(hosts.surface(on: 1) == .dropTarget)
        hosts.wheelHidden()
        #expect(registered(hosts) == [.fileURL])
        hosts.close()
    }

    @Test func aDropTargetRequestedWhileTheWheelShowsIsNotRegistered() throws {
        let (hosts, _) = try rig()
        hosts.wheelShown()
        hosts.request(Self.drop, from: .tray)
        #expect(registered(hosts).isEmpty)
        hosts.close()
    }

    @Test func closingUnregisters() throws {
        let (hosts, _) = try rig()
        hosts.request(Self.drop, from: .tray)
        let host = try #require(hosts.host(on: 1))
        hosts.close()
        #expect(host.tracking.registeredDraggedTypes.isEmpty)
    }

    @Test func aDropReachesTheClientWithItsDisplay() throws {
        let (hosts, tray) = try rig()
        hosts.request(Self.drop, from: .tray)
        let board = NSPasteboard(name: NSPasteboard.Name("app.zivlet.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([URL(filePath: "/tmp/a.png") as NSURL, URL(filePath: "/tmp/b.png") as NSURL])
        let info = FakeDraggingInfo(pasteboard: board)
        let view = try #require(hosts.host(on: 1)?.tracking)
        #expect(view.draggingEntered(info) == .copy)
        #expect(view.draggingUpdated(info) == .copy)
        #expect(view.prepareForDragOperation(info))
        #expect(view.performDragOperation(info))
        view.draggingExited(info)
        #expect(tray.entered == [1] && tray.updated == [1] && tray.exited == [1])
        #expect(tray.dropped.map(\.display) == [1] && tray.dropped.map(\.items) == [2])
        hosts.close()
    }

    @Test func aClientThatTakesNoDropsIsNeverRegistered() throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchOnly(), clock: ManualClock(), animation: .instant)
        hosts.register(FakeClient(), as: .hud)
        hosts.request(
            IslandRequest(client: .hud, display: 1, resting: .dropTarget, hoverSurface: .dropTarget), from: .hud)
        #expect(registered(hosts).isEmpty)
        let view = try #require(hosts.host(on: 1)?.tracking)
        let board = NSPasteboard(name: NSPasteboard.Name("app.zivlet.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: board)) == [])
        #expect(!view.performDragOperation(FakeDraggingInfo(pasteboard: board)))
        hosts.close()
    }
}
