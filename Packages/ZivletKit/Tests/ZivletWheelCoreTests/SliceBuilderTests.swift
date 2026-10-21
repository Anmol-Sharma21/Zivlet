import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Slice lists per mode (03a §2.6)")
struct SliceBuilderTests {
    let builder = SliceBuilder()

    func targets(_ content: WheelContent) -> [SliceTarget] { content.slices.map(\.target) }
    func files(_ formats: FormatID...) -> [SelectionItem] { formats.map { SelectionItem($0) } }

    @Test func singleFormatUsesCatalogOrder() {
        let content = builder.content(for: .convert, items: files(.png))
        #expect(targets(content) == [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf].map(SliceTarget.convert))
        #expect(content.slices.first?.label == "JPG" && content.slices.first?.id == "convert.jpg")
    }

    @Test func sameFamilyKeepsFirstFormatsSharedTargets() {
        let content = builder.content(for: .convert, items: files(.jpg, .png, .png))
        #expect(targets(content) == [.webp, .heic, .tiff, .avif, .bmp, .pdf].map(SliceTarget.convert))
        #expect(content.slices.allSatisfy { $0.badge == nil })
    }

    @Test func gifMixesAsVideoAndPdfAsDocument() {
        #expect(
            targets(builder.content(for: .convert, items: files(.mp4, .gif)))
                == [.mov, .mkv, .webm, .avi, .wmv].map(SliceTarget.convert))
        #expect(
            targets(builder.content(for: .convert, items: files(.docx, .pdf)))
                == [.pages, .txt, .md, .epub, .png, .jpg].map(SliceTarget.convert))
    }

    @Test func mixedFamiliesGiveBadgedUnionWhenItFits() {
        let content = builder.content(for: .convert, items: files(.jpg, .srt, .srt))
        #expect(content.slices.count == 9)
        #expect(content.slices.first?.badge == "1 of 3")
        #expect(content.slices.last?.target == .convert(.txt))
        #expect(content.slices.last?.badge == "2 of 3")
    }

    @Test func mixedFamiliesOverTwelveSlotsAreEmpty() {
        #expect(builder.content(for: .convert, items: files(.jpg, .mp3)) == .empty(.noCommonFormat))
    }

    @Test(arguments: [
        ([SelectionItem](), WheelMode.convert, EmptyReason.noItems),
        ([SelectionItem(nil, kind: .folder)], .convert, .foldersCannotConvert),
        ([SelectionItem(.png), SelectionItem(nil, kind: .folder)], .convert, .foldersCannotConvert),
        ([SelectionItem(.png, isLocal: false)], .convert, .inaccessible),
        ([SelectionItem(nil)], .convert, .unsupportedFile),
        ([SelectionItem(.ogg)], .tools, .noTools(.ogg)),
        ([SelectionItem(.jpg), SelectionItem(.mp4)], .tools, .noTools(nil)),
        ([SelectionItem(nil, kind: .folder)], .tools, .noTools(nil)),
        ([SelectionItem(.jpg, isLocal: false)], .tools, .inaccessible),
        ([SelectionItem(.jpg, isLocal: false)], .actions, .onlyLocalItems),
    ])
    func emptyStates(items: [SelectionItem], mode: WheelMode, reason: EmptyReason) {
        #expect(builder.content(for: mode, items: items) == .empty(reason))
    }

    @Test func packagesConvertLikeFiles() {
        let content = builder.content(for: .convert, items: [SelectionItem(.pages, kind: .package)])
        #expect(targets(content).first == .convert(.docx))
    }

    @Test func capabilityGateHidesTargetsAndExplainsWhenNothingIsLeft() {
        let noWebM = CapabilitySnapshot(unavailableTargets: [.webm])
        #expect(
            !targets(builder.content(for: .convert, items: files(.mp4), capabilities: noWebM)).contains(.convert(.webm))
        )
        let noArchives = CapabilitySnapshot(unavailableTargets: [.tar, .gz])
        #expect(
            builder.content(for: .convert, items: files(.zip), capabilities: noArchives)
                == .empty(.noInstalledConverter(.zip)))
    }

    @Test func toolsUseTheTotalItemCount() {
        let one = builder.content(for: .tools, items: files(.mp4))
        let two = builder.content(for: .tools, items: files(.mp4, .mov))
        #expect(one.slices.count == 9)
        #expect(targets(two) == [.shrink, .stripMetadata, .videoMute, .videoJoin].map(SliceTarget.tool))
        #expect(two.slices.first?.symbolName != nil)
    }

    @Test func actionsAreAlwaysTheSixIncludingFolders() {
        let items = [SelectionItem(nil, kind: .folder), SelectionItem(.xlsx), SelectionItem(nil)]
        let content = builder.content(for: .actions, items: items)
        #expect(targets(content) == ActionID.allCases.map(SliceTarget.action))
    }

    @Test func emptyStateCopy() {
        #expect(builder.message(for: .noInstalledConverter(.gz)) == "GZIP needs an engine that isn't installed")
        #expect(builder.message(for: .noTools(.ogg)) == "No tools for OGG files")
        #expect(builder.message(for: .noTools(nil)) == "No tools for these items")
        #expect(builder.message(for: .foldersCannotConvert) == "Folders work with Actions only")
    }

    @Test func acceptedModesFeedTheTrigger() {
        #expect(builder.acceptedModes(items: files(.ogg)) == [.convert, .actions])
        #expect(builder.acceptedModes(items: [SelectionItem(nil, kind: .folder)]) == [.actions])
        #expect(builder.acceptedModes(items: files(.png)) == Set(WheelMode.allCases))
    }
}
