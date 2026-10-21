/// Immutable tool registry with the per-format selection rule (P0-14, 03a §2.6).
public struct ToolCatalog: Sendable {
    public static let standard = ToolCatalog(registry: .standard)

    /// Every tool in wheel order (06b Task 4b).
    public let specs: [ToolSpec]
    private let specsByID: [ToolID: ToolSpec]
    private let registry: FormatRegistry

    public init(registry: FormatRegistry) {
        self.specs = Self.specTable
        self.specsByID = Dictionary(Self.specTable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.registry = registry
    }

    /// The spec for `id`. Every `ToolID` is in the spec table, so a miss is a programming error.
    public func spec(_ id: ToolID) -> ToolSpec {
        guard let spec = specsByID[id] else {
            preconditionFailure("Tool table has no entry for \(id)")
        }
        return spec
    }

    /// One FormatID per selected item; the item count is formats.count.
    public func tools(for formats: [FormatID]) -> [ToolID] {
        guard let first = formats.first else { return [] }
        let distinct = formats.uniqued()
        let count = formats.count
        if distinct.count == 1 { return tools(for: first, count: count) }
        let shared = sharedTools(distinct, count: count)
        if !shared.isEmpty { return shared }
        return distinct.allSatisfy(qualifiesForQRScan) ? [.qrScan] : []
    }

    /// `row.multi` when `count >= 2`, else `row.single`; empty for formats without tools.
    func tools(for format: FormatID, count: Int) -> [ToolID] {
        guard let row = Self.applicability.first(where: { $0.formats.contains(format) }) else { return [] }
        return count >= 2 ? row.multi : row.single
    }

    /// Same mixing family → intersection of the per-format lists in the first format's order; else empty.
    private func sharedTools(_ distinct: [FormatID], count: Int) -> [ToolID] {
        let families = Set(distinct.map { registry.format($0).family })
        guard families.count == 1, let first = distinct.first else { return [] }
        let others = distinct.dropFirst().map { Set(tools(for: $0, count: count)) }
        return tools(for: first, count: count).filter { tool in others.allSatisfy { $0.contains(tool) } }
    }

    /// Read QR survives a mixed selection when every format is an image, a GIF or a PDF.
    private func qualifiesForQRScan(_ format: FormatID) -> Bool {
        format == .gif || format == .pdf || registry.format(format).family == .image
    }
}
