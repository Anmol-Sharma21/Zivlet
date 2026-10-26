import Testing

@testable import ZivletCore

@Suite("Tool visibility marks (P2-100, FR-90)")
struct ToolVisibilityTests {
    @Test func extrasAreLeftOffTheWheelButStayReachable() {
        let catalog = ToolCatalog(
            registry: .standard, specs: ToolCatalog.specTable,
            applicability: [.init(formats: [.png], single: [.visible(.shrink), .extra(.imageBackdrop)], multi: [])])
        #expect(catalog.tools(for: [.png]) == [.shrink])
        #expect(catalog.extras(for: [.png]) == [.imageBackdrop])
    }

    @Test func extrasFollowTheItemCount() {
        let catalog = ToolCatalog(
            registry: .standard, specs: ToolCatalog.specTable,
            applicability: [
                .init(formats: [.png], single: [.visible(.shrink)], multi: [.visible(.shrink), .extra(.imageCollage)])
            ])
        #expect(catalog.extras(for: [.png]).isEmpty)
        #expect(catalog.extras(for: [.png, .png]) == [.imageCollage])
        #expect(catalog.tools(for: [.png, .png]) == [.shrink])
    }

    /// D-M6-17: every tool in the standard table is visible by default.
    @Test func everyStandardToolIsVisibleByDefault() {
        let entries = ToolCatalog.applicability.flatMap { $0.single + $0.multi }
        #expect(entries.allSatisfy { $0.visibility == .defaultVisible })
        #expect(FormatID.allCases.allSatisfy { ToolCatalog.standard.extras(for: [$0]).isEmpty })
    }
}
