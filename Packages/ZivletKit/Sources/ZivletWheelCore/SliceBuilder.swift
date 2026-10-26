import ZivletCore

/// Derives the per-mode slice lists and empty states for a selection (03a §2.6). Every list shows at most
/// `maxSlots` slices in catalog order (P2-100).
/// Slice ids are "<mode>.<rawValue>" (for example "tools.shrink"), stable for the glass morph.
public struct SliceBuilder: Sendable {
    let conversions: ConversionCatalog
    let tools: ToolCatalog
    let registry: FormatRegistry
    let maxSlots: Int

    public init(
        conversions: ConversionCatalog = .standard, tools: ToolCatalog = .standard,
        registry: FormatRegistry = .standard, maxSlots: Int = WheelLimits.maxSlots
    ) {
        self.conversions = conversions
        self.tools = tools
        self.registry = registry
        self.maxSlots = maxSlots
    }

    /// Empty selection → `.noItems`; otherwise the rules of the selected mode.
    public func content(
        for mode: WheelMode, items: [SelectionItem],
        capabilities: CapabilitySnapshot = .full
    ) -> WheelContent {
        guard !items.isEmpty else { return .empty(.noItems) }
        switch mode {
        case .convert: return convertContent(items, capabilities)
        case .tools: return toolContent(items)
        case .actions: return actionContent(items, capabilities)
        }
    }

    /// Empty-state copy using this builder's registry.
    public func message(for reason: EmptyReason) -> String { reason.message(using: registry) }

    /// The modes whose content is non-empty; the trigger host puts this in `DragSummary.acceptedModes`.
    public func acceptedModes(
        items: [SelectionItem], capabilities: CapabilitySnapshot = .full
    ) -> Set<WheelMode> {
        Set(
            WheelMode.allCases.filter { mode in
                !content(for: mode, items: items, capabilities: capabilities).slices.isEmpty
            })
    }

    /// Files only, every item counted (03a §2.6); folders or unknown formats have no tools.
    private func toolContent(_ items: [SelectionItem]) -> WheelContent {
        guard items.allSatisfy(\.isLocal) else { return .empty(.inaccessible) }
        let formats = items.compactMap(\.format)
        let filesOnly = items.allSatisfy { $0.kind != .folder }
        guard filesOnly, formats.count == items.count else { return .empty(.noTools(nil)) }
        let ids = tools.tools(for: formats)
        guard !ids.isEmpty else {
            let distinct = formats.uniqued()
            return .empty(.noTools(distinct.count == 1 ? distinct.first : nil))
        }
        return .slices(ids.prefix(maxSlots).map(toolSlice))
    }

    /// The actions in fixed order for any local selection, folders included (03a §2.6), minus unavailable ones.
    private func actionContent(_ items: [SelectionItem], _ caps: CapabilitySnapshot) -> WheelContent {
        guard items.allSatisfy(\.isLocal) else { return .empty(.onlyLocalItems) }
        let available = ActionID.allCases.filter { !caps.unavailableActions.contains($0) }
        return .slices(available.prefix(maxSlots).map(actionSlice))
    }

    private func toolSlice(_ id: ToolID) -> WheelSlice {
        let spec = tools.spec(id)
        return WheelSlice(
            id: "tools.\(id.rawValue)", label: spec.wheelLabel, symbolName: spec.symbolName,
            target: .tool(id), badge: nil)
    }

    private func actionSlice(_ id: ActionID) -> WheelSlice {
        WheelSlice(
            id: "actions.\(id.rawValue)", label: id.wheelLabel, symbolName: id.symbolName,
            target: .action(id), badge: nil)
    }
}
