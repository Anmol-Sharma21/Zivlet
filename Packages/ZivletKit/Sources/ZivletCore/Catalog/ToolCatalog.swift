/// Immutable tool registry with the per-format selection rule (P0-14, 03a §2.6).
public struct ToolCatalog: Sendable {
    public static let standard = ToolCatalog(registry: .standard)

    /// Every tool in wheel order (06b Task 4b).
    public let specs: [ToolSpec]
    private let specsByID: [ToolID: ToolSpec]
    private let registry: FormatRegistry
    private let applicability: [ApplicabilityRow]

    public init(registry: FormatRegistry) {
        self.init(registry: registry, specs: Self.specTable, applicability: Self.applicability)
    }

    /// Tests pass their own tables (P2-100 lint and visibility tests).
    init(registry: FormatRegistry, specs: [ToolSpec], applicability: [ApplicabilityRow]) {
        self.specs = specs
        self.specsByID = Dictionary(specs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.registry = registry
        self.applicability = applicability
    }

    /// The spec for `id`. Every `ToolID` is in the spec table, so a miss is a programming error.
    public func spec(_ id: ToolID) -> ToolSpec {
        guard let spec = specsByID[id] else {
            preconditionFailure("Tool table has no entry for \(id)")
        }
        return spec
    }

    /// The wheel's tools: one FormatID per selected item; the item count is formats.count. Extras are left out.
    public func tools(for formats: [FormatID]) -> [ToolID] {
        tools(for: formats, visibility: .defaultVisible)
    }

    /// The tools that apply but are marked extra: for custom wheels, App Intents and the CLI (P2-100).
    public func extras(for formats: [FormatID]) -> [ToolID] {
        tools(for: formats, visibility: .extra)
    }

    /// One format → its row; a same-family mix → the intersection of its rows; if that is empty or the families
    /// differ → the combining tools that accept every item (P2-100).
    private func tools(for formats: [FormatID], visibility: ToolVisibility) -> [ToolID] {
        guard let first = formats.first else { return [] }
        let distinct = formats.uniqued()
        let count = formats.count
        if distinct.count == 1 { return tools(for: first, count: count, visibility: visibility) }
        let shared = sharedTools(distinct, count: count, visibility: visibility)
        if !shared.isEmpty { return shared }
        return combiningTools(distinct, count: count, visibility: visibility)
    }

    /// The row's entries for `count` items with this visibility; empty for formats without tools.
    func tools(for format: FormatID, count: Int, visibility: ToolVisibility = .defaultVisible) -> [ToolID] {
        guard let row = applicability.first(where: { $0.formats.contains(format) }) else { return [] }
        return row.entries(count: count).filter { $0.visibility == visibility }.map(\.id)
    }

    /// Same mixing family → intersection of the per-format lists in the first format's order; else empty.
    private func sharedTools(_ distinct: [FormatID], count: Int, visibility: ToolVisibility) -> [ToolID] {
        let families = Set(distinct.map { registry.format($0).family })
        guard families.count == 1, let first = distinct.first else { return [] }
        let others = distinct.dropFirst().map { Set(tools(for: $0, count: count, visibility: visibility)) }
        return tools(for: first, count: count, visibility: visibility).filter { tool in
            others.allSatisfy { $0.contains(tool) }
        }
    }

    /// Tools in catalog order whose `accepts` covers every format and whose cardinality allows `count`.
    private func combiningTools(_ distinct: [FormatID], count: Int, visibility: ToolVisibility) -> [ToolID] {
        specs.filter { spec in
            guard let accepts = spec.accepts, accepts.isSuperset(of: distinct), allows(spec.cardinality, count) else {
                return false
            }
            return mixVisibility(spec.id, distinct, count: count) == visibility
        }.map(\.id)
    }

    /// A combining tool marked extra in any of the mixed formats' rows stays extra in the mix.
    private func mixVisibility(_ id: ToolID, _ distinct: [FormatID], count: Int) -> ToolVisibility {
        let marked = distinct.contains { tools(for: $0, count: count, visibility: .extra).contains(id) }
        return marked ? .extra : .defaultVisible
    }

    private func allows(_ cardinality: ToolCardinality, _ count: Int) -> Bool {
        switch cardinality {
        case .single: count == 1
        case .multiAllowed: count >= 1
        case .multiOnly: count >= 2
        }
    }
}
