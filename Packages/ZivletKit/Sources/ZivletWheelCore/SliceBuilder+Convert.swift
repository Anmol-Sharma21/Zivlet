import ZivletCore

// Conversion slices: one format, same family (shared targets), or mixed families (badged union).
extension SliceBuilder {
    func convertContent(_ items: [SelectionItem], _ caps: CapabilitySnapshot) -> WheelContent {
        guard items.allSatisfy(\.isLocal) else { return .empty(.inaccessible) }
        if items.contains(where: { $0.kind == .folder }) { return .empty(.foldersCannotConvert) }
        let formats = items.compactMap(\.format)
        guard formats.count == items.count else { return .empty(.unsupportedFile) }
        let distinct = formats.uniqued()
        let families = distinct.map { registry.format($0).family }.uniqued()
        if families.count == 1 { return sameFamily(distinct, caps) }
        return mixedFamilies(formats, families: families, caps)
    }

    /// First format's targets that every other format can also produce, in that order (03a §2.6).
    private func sameFamily(_ formats: [FormatID], _ caps: CapabilitySnapshot) -> WheelContent {
        let shared = sharedTargets(formats)
        let available = shared.filter { !caps.unavailableTargets.contains($0) }
        if !available.isEmpty { return .slices(available.prefix(maxSlots).map { slice($0, badge: nil) }) }
        if formats.count == 1, !shared.isEmpty { return .empty(.noInstalledConverter(formats[0])) }
        return .empty(formats.count == 1 ? .unsupportedFile : .noCommonFormat)
    }

    /// Zivlet addition (03a §2.6, 06 P0-8): union grouped by family, badged "k of n", only if ≤ 12 slots.
    private func mixedFamilies(
        _ formats: [FormatID], families: [FormatFamily],
        _ caps: CapabilitySnapshot
    ) -> WheelContent {
        let ordered = families.flatMap { family in
            sharedTargets(formats.uniqued().filter { registry.format($0).family == family })
        }.uniqued().filter { !caps.unavailableTargets.contains($0) }
        guard !ordered.isEmpty, ordered.count <= maxSlots else { return .empty(.noCommonFormat) }
        return .slices(
            ordered.map { target in
                let able = formats.filter { conversions.canConvert($0, to: target) }.count
                return slice(target, badge: able < formats.count ? "\(able) of \(formats.count)" : nil)
            })
    }

    private func sharedTargets(_ formats: [FormatID]) -> [FormatID] {
        guard let first = formats.first else { return [] }
        return conversions.targets(for: first).filter { target in
            formats.dropFirst().allSatisfy { conversions.canConvert($0, to: target) }
        }
    }

    private func slice(_ target: FormatID, badge: String?) -> WheelSlice {
        WheelSlice(
            id: "convert.\(target.rawValue)", label: registry.format(target).wheelLabel, symbolName: nil,
            target: .convert(target), badge: badge)
    }
}
