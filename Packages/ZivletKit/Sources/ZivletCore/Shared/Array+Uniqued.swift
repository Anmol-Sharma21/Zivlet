extension Array where Element: Hashable {
    /// First occurrence of each element, order kept.
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
