#if DEBUG
    import AppKit
    import Testing
    import ZivletShelfCore

    @testable import ZivletBox

    @Suite("Drop Box debug previews (D-M5b-20)")
    @MainActor
    struct BoxShotFlagsTests {
        @Test func noFlagsMeansNoPreview() throws {
            #expect(try BoxShotFlags.parse(arguments: ["Zivlet"]) == BoxShotFlags())
        }

        @Test(arguments: BoxShotFlags.State.allCases)
        func everyStateParses(_ state: BoxShotFlags.State) throws {
            #expect(try BoxShotFlags.parse(arguments: ["Z", "-ZivletBoxPreview", state.rawValue]).preview == state)
        }

        @Test(arguments: BoxShotFlags.TrayState.allCases)
        func everyTrayStateParses(_ state: BoxShotFlags.TrayState) throws {
            #expect(
                try BoxShotFlags.parse(arguments: ["Z", "-ZivletTrayPreview", state.rawValue]).trayPreview == state)
        }

        @Test func anUnknownTrayStateIsRefused() {
            #expect(throws: BoxShotFlags.Invalid.unknown("-ZivletTrayPreview", "open")) {
                try BoxShotFlags.parse(arguments: ["Z", "-ZivletTrayPreview", "open"])
            }
        }

        @Test func anUnknownStateIsRefusedNamingOnlyTheFlag() {
            #expect(throws: BoxShotFlags.Invalid.unknown("-ZivletBoxPreview", "sideways")) {
                try BoxShotFlags.parse(arguments: ["Z", "-ZivletBoxPreview", "sideways"])
            }
            #expect(
                BoxShotFlags.Invalid.unknown("-ZivletBoxPreview", "secret").logDescription
                    == "unknown value for -ZivletBoxPreview")
            #expect(throws: BoxShotFlags.Invalid.missingValue("-ZivletBoxPreview")) {
                try BoxShotFlags.parse(arguments: ["Z", "-ZivletBoxPreview"])
            }
            #expect(BoxShotFlags.Invalid.missingValue("-ZivletBoxDemo").logDescription == "no value for -ZivletBoxDemo")
        }

        @Test func theDemoFolderMustBeAbsolute() throws {
            let flags = try BoxShotFlags.parse(arguments: ["Z", "-ZivletBoxDemo", "/tmp/box-demo"])
            #expect(flags.demoFolder == URL(filePath: "/tmp/box-demo", directoryHint: .isDirectory))
            #expect(throws: BoxShotFlags.Invalid.relativeFolder("-ZivletBoxDemo")) {
                try BoxShotFlags.parse(arguments: ["Z", "-ZivletBoxDemo", "demo"])
            }
            #expect(
                BoxShotFlags.Invalid.relativeFolder("-ZivletBoxDemo").logDescription
                    == "not an absolute folder for -ZivletBoxDemo")
        }

        @Test(arguments: BoxShotFlags.State.allCases)
        func everyPreviewStateDrawsMadeUpItems(_ state: BoxShotFlags.State) {
            let model = BoxPreview.model(state, finish: .glass, maxHeight: 600) { _ in NSImage() }
            #expect(model.items.isEmpty == (state == .empty))
            #expect(model.items.allSatisfy { $0.status != nil })
        }

        @Test func eachPreviewIsTheStateItNames() {
            func model(_ s: BoxShotFlags.State) -> BoxViewModel {
                BoxPreview.model(s, finish: .solid, maxHeight: 600) { _ in NSImage() }
            }
            #expect(model(.hidden).presentation.base == .hidden)
            #expect(model(.docked).presentation.base == .docked(.right))
            #expect(model(.collapsed).presentation.base == .collapsed)
            #expect(model(.list).viewMode == .list && model(.grid).viewMode == .grid)
            #expect(model(.selection).selection.count == 3)
            #expect(model(.dropTarget).presentation.overlay == .dropTarget(count: 3))
            #expect(model(.attention).missingCount == 3)
            #expect(model(.confirmTrash).presentation.overlay == .confirm(.trash(count: 3)))
            #expect(model(.confirmClear).presentation.overlay == .confirm(.clear))
            #expect(model(.confirmEmpty).presentation.overlay == .confirm(.emptyStorage))
            #expect(model(.storageWarning).storageWarning && !model(.grid).storageWarning)
            if case .busy = model(.busy).presentation.overlay {} else { Issue.record("not busy") }
        }

        @Test func theFrameLineUsesWholePointsFromTheTop() {
            let line = BoxPreview.frameLine(CGRect(x: 10.4, y: 100.6, width: 384, height: 178.2), screenTop: 1169)
            #expect(line == "Box: frame 10 890 384 178")
        }
    }
#endif
