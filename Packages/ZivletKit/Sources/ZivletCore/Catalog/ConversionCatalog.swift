/// One source → target conversion (03a §3.3).
public struct ConversionPair: Sendable, Hashable, Codable {
    public let source: FormatID
    public let target: FormatID

    public init(source: FormatID, target: FormatID) {
        self.source = source
        self.target = target
    }
}

/// One source and its targets in petal order.
public struct ConversionRow: Sendable, Hashable {
    public let source: FormatID
    public let targets: [FormatID]

    public init(_ source: FormatID, _ targets: [FormatID]) {
        self.source = source
        self.targets = targets
    }
}

/// Immutable conversion matrix (P0-12). Each row lists a source's targets in petal order.
public struct ConversionCatalog: Sendable {
    /// The built-in table; `CatalogValidationTests` checks it against `init(rows:registry:)`.
    public static let standard = ConversionCatalog(validated: table, registry: .standard)

    /// Every pair, rows flattened in order.
    public let pairs: [ConversionPair]
    private let targetsBySource: [FormatID: [FormatID]]
    private let registry: FormatRegistry

    /// Refuses a row that targets its own source, repeats a target, or repeats a source.
    public init(rows: [ConversionRow], registry: FormatRegistry) throws(CatalogError) {
        var sources: Set<FormatID> = []
        for row in rows {
            guard sources.insert(row.source).inserted else { throw .duplicateRow(row.source) }
            if row.targets.contains(row.source) { throw .selfTarget(row.source) }
            if let repeated = Self.firstRepeat(row.targets) { throw .duplicateTarget(row.source, repeated) }
        }
        self.init(validated: rows, registry: registry)
    }

    private init(validated rows: [ConversionRow], registry: FormatRegistry) {
        self.pairs = rows.flatMap { row in row.targets.map { ConversionPair(source: row.source, target: $0) } }
        self.targetsBySource = Dictionary(rows.map { ($0.source, $0.targets) }, uniquingKeysWith: { first, _ in first })
        self.registry = registry
    }

    private static func firstRepeat(_ targets: [FormatID]) -> FormatID? {
        var seen: Set<FormatID> = []
        return targets.first { !seen.insert($0).inserted }
    }

    /// Targets for `source` in petal order; empty for formats without a row (html).
    public func targets(for source: FormatID) -> [FormatID] {
        targetsBySource[source] ?? []
    }

    public func canConvert(_ source: FormatID, to target: FormatID) -> Bool {
        targets(for: source).contains(target)
    }

    /// Number of pairs whose SOURCE format is in `category` (03a §3.3).
    public func pairCount(in category: FormatCategory) -> Int {
        pairs.count { registry.format($0.source).category == category }
    }

    public var distinctTargets: Set<FormatID> {
        Set(pairs.map(\.target))
    }
}
