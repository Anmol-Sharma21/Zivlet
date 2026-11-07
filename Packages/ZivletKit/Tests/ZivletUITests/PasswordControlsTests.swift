import Foundation
import Testing
import ZivletNotch

@testable import ZivletUI

/// The sheet's own choice controls (review of M7): the selected Printing segment and the checkboxes use no accent
/// colour, every word holds 4.5:1 on glass and the solid finish, and VoiceOver reads the owner password itself.
@Suite("The sheet's choices hold their contrast and read their values")
@MainActor
struct PasswordControlsTests {
    @Test func theSelectedSegmentIsBlackOnWhite() {
        #expect(PasswordChoiceLook.selectedFillGrey == 1 && PasswordChoiceLook.selectedInkGrey == 0)
        #expect(PasswordChoiceLook.selectedContrast >= 4.5)
    }

    @Test func theOtherSegmentsAndTheChecksAreWhiteOnEveryFinish() {
        let surfaces = [IslandLook.worstGlassLuminance, IslandInk.luminance(IslandLook.solidGrey), 0]
        for surface in surfaces {
            #expect(IslandInk.contrast(textOpacity: 1, over: surface) >= 4.5)
        }
    }

    @Test func thePrintingChoicesFillTheRowFromItsLeadingEdge() {
        #expect(PasswordChoiceLook.segmentsFillTheRow)
    }

    @Test func voiceOverReadsTheOwnerPasswordAfterItsCaption() {
        let read = PasswordRestrictionsSection.ownerAccessibility("Kq7-w2Zp")
        #expect(read.label == PasswordCopy.ownerShownOnce && read.value == "Kq7-w2Zp")
    }
}
