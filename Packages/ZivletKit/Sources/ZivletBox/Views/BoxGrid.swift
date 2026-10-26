import SwiftUI

/// The grid (19c §3.2): five 64 pt columns, 8 pt apart both ways.
struct BoxGrid: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(BoxLook.Grid.cell), spacing: BoxLook.Grid.gap, alignment: .top),
            count: BoxLook.Grid.columns)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: BoxLook.Grid.gap) {
            ForEach(model.items) { BoxCell(item: $0, model: model, press: press) }
        }
    }
}
