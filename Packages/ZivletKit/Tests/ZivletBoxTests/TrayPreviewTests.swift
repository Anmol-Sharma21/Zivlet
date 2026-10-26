#if DEBUG
    import AppKit
    import NotchTestSupport
    import Testing
    import ZivletNotch
    import ZivletNotchCore

    @testable import ZivletBox

    @Suite("Tray debug previews (D-M5b-20)")
    @MainActor
    struct TrayPreviewTests {
        @Test(arguments: [
            (BoxShotFlags.TrayState.dropTarget, IslandSurface.dropTarget), (.toast, .toast), (.compact, .expanded),
            (.sensor, .sensor),
        ])
        func eachStateShowsItsSurfaceWithoutTheKeyboard(_ state: BoxShotFlags.TrayState, _ surface: IslandSurface)
            async throws
        {
            let box = TrayPreviewBox(icon: { _ in NSImage() })
            let rig = try TrayRig(box: box)
            rig.tray.preview(state, on: 1)
            #expect(rig.hosts.surface(on: 1) == surface)
            #expect(rig.hosts.host(on: 1)?.isKey == false)
            _ = rig.tray.content(for: surface, display: 1)
            let board = NSPasteboard(name: NSPasteboard.Name("app.zivlet.test.\(UUID().uuidString)"))
            _ = await box.addDrop(board)
            board.releaseGlobally()
            box.undoAdd([])
            box.showPanel(.saved)
            box.press(.share)
            #expect(box.trayModel.items.count == 8)
        }
    }
#endif
