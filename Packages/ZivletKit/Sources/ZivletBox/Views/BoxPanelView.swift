import SwiftUI
import ZivletNotch
import ZivletShelfCore

/// The panel's content for every state (19c §4.1): nothing when hidden, the tab when docked, the short card when
/// collapsed, the full card when expanded; the drop target dims whatever it covers.
public struct BoxPanelView: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    public init(model: BoxViewModel, press: @escaping (BoxPress) -> Void) {
        self.model = model
        self.press = press
    }

    public var body: some View {
        switch model.presentation.base {
        case .hidden:
            EmptyView()
        case .docked(let edge):
            BoxDockTab(model: model, edge: edge, press: press)
        case .collapsed:
            BoxCard(finish: model.finish, size: BoxLayout.size(of: model)) {
                dimmed(BoxCollapsedCard(model: model, press: press)).frame(maxHeight: .infinity)
            }
        case .expanded:
            BoxCard(finish: model.finish, size: BoxLayout.size(of: model)) {
                BoxExpandedCard(model: model, press: press)
            }
        }
    }

    private func dimmed(_ content: some View) -> some View {
        let count: Int? = {
            if case .dropTarget(let count) = model.presentation.overlay { return count }
            return nil
        }()
        return
            content
            .opacity(count == nil ? 1 : BoxLook.dropDim)
            .overlay { if let count { BoxDropOverlay(count: count) } }
    }
}

/// Expanded (19c §4.1): header, the grid or list (scrolling past the panel's maximum), the action bar. One
/// accessibility list holds the items.
struct BoxExpandedCard: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    private var dropCount: Int? {
        if case .dropTarget(let count) = model.presentation.overlay { return count }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BoxLook.Panel.sectionGap) {
            BoxHeader(model: model, press: press)
            items
                .frame(height: BoxLayout.visibleContentHeight(model), alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(BoxAccessibility(model).listLabel)
                .accessibilityValue(BoxAccessibility(model).value)
            BoxActionBar(model: model, press: press)
        }
        .padding(IslandContentLook.Spacing.l)
        .opacity(dropCount == nil ? 1 : BoxLook.dropDim)
        .overlay { if let dropCount { BoxDropOverlay(count: dropCount) } }
    }

    @ViewBuilder private var items: some View {
        if model.items.isEmpty {
            BoxEmpty()
        } else if BoxLayout.scrolls(model) {
            ScrollView(.vertical) { list }.scrollIndicators(.automatic)
        } else {
            list
        }
    }

    @ViewBuilder private var list: some View {
        switch model.viewMode {
        case .grid: BoxGrid(model: model, press: press)
        case .list: BoxList(model: model, press: press)
        }
    }
}
