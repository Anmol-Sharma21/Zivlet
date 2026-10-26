@testable import ZivletCore

extension ToolCatalog {
    /// The standard catalog with `count` visible single-item tools for `format`, for cap tests (P2-100).
    static func withVisibleTools(_ count: Int, for format: FormatID) -> ToolCatalog {
        let ids = specTable.filter { $0.cardinality != .multiOnly }.prefix(count).map(\.id)
        let row = ApplicabilityRow(formats: [format], single: ids.map(ApplicabilityRow.Entry.visible), multi: [])
        return ToolCatalog(registry: .standard, specs: specTable, applicability: [row])
    }
}
