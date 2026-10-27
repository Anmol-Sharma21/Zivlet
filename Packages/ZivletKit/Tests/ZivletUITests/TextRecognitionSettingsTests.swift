import AppKit
import SwiftUI
import Testing
import ZivletCore
import ZivletSettings

@testable import ZivletUI

@Suite("Settings › General › Text recognition (plan 18d D13, D-M6-14)")
@MainActor
struct TextRecognitionSettingsTests {
    @Test func theRowOffersThreeChoicesInZivletsWords() {
        #expect(TextRecognitionSection.title == "Text recognition")
        #expect(
            TextLanguageChoice.allCases.map(TextRecognitionSection.label) == [
                "Match my languages", "Hindi and English", "English",
            ])
    }

    @Test func withHindiEveryChoiceIsOffered() {
        let rows = TextRecognitionSection.rows(hindiAvailable: true)
        #expect(rows.map(\.choice) == [.matchMine, .hindiAndEnglish, .english])
        #expect(rows.allSatisfy { $0.enabled })
        #expect(TextRecognitionSection.help(hindiAvailable: true) == nil)
    }

    @Test func withoutHindiTheHindiChoiceIsDisabledAndExplained() {
        let rows = TextRecognitionSection.rows(hindiAvailable: false)
        #expect(rows.first { $0.choice == .hindiAndEnglish }?.enabled == false)
        #expect(rows.first { $0.choice == .english }?.enabled == true)
        #expect(TextRecognitionSection.help(hindiAvailable: false) == "Hindi isn't available on this version of macOS.")
    }

    @Test func choosingStoresTheValue() {
        let model = SettingsModel.preview
        model.set(\.text.language, .english)
        #expect(model.settings.text.language == .english)
    }

    @Test func theSectionRenders() {
        let model = SettingsModel.preview
        model.hindiAvailable = false
        let image = ImageRenderer(content: Form { TextRecognitionSection(model: model) }.frame(width: 520)).nsImage
        #expect((image?.size.height ?? 0) > 40)
    }
}
