import AppKit
import Testing
import ZivletActions
import ZivletCore
import ZivletShelfCore

@testable import ZivletBox

@Suite("The BOX slice through the controller (P2-55 §9.5, OWN-APP-1)")
@MainActor
struct BoxSliceAddingTests {
    @Test func addedItemsAreAToastAndTheBoxOpensAtTheDrop() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let point = Point2D(x: BoxRig.display.midX, y: BoxRig.display.midY)
        let slice = BoxSliceAdding(controller: box, newBoxByDefault: { false }, dropPoint: { point })
        let result = await slice.add(try rig.files(3), newBox: false)
        #expect(result == .done(toast: "Added 3", undo: nil))
        #expect(box.presentation.base == .expanded && box.panel.isVisible)
        #expect(abs(Rect2D(box.panel.frame).midX - point.x) < 1)
        box.hidePanel()
    }

    @Test func theSettingOrOptionMakesANewBox() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        var newByDefault = false
        let slice = BoxSliceAdding(controller: box, newBoxByDefault: { newByDefault }, dropPoint: { nil })
        _ = await slice.add(try rig.files(1, prefix: "a"), newBox: false)
        _ = await slice.add(try rig.files(1, prefix: "b"), newBox: true)
        newByDefault = true
        _ = await slice.add(try rig.files(1, prefix: "c"), newBox: false)
        #expect(box.library.boxes.count == 3)
        box.hidePanel()
    }

    @Test func outcomesBecomeToastsAndCards() {
        #expect(AddOutcome(added: 2).actionResult == .done(toast: "Added 2", undo: nil))
        #expect(
            AddOutcome(added: 1, duplicates: ["a.txt"]).actionResult
                == .partial(
                    toast: "Added 1",
                    card: ActionCard(title: "Some items weren't added.", lines: ["a.txt is already in the box."]),
                    undo: nil))
        #expect(
            AddOutcome(added: 0, duplicates: ["a.txt", "b.txt"]).actionResult
                == .done(toast: "Already in the box", undo: nil))
        #expect(
            AddOutcome(added: 0, rejected: ["x: y"], failure: "Only items stored on this Mac can be added").actionResult
                == .failed(ActionCard(title: "Only items stored on this Mac can be added.", lines: ["x: y"])))
        #expect(AddOutcome(added: 0).actionResult == .failed(ActionCard(title: "Nothing was added.")))
    }
}
