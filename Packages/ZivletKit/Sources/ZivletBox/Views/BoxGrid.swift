import SwiftUI
import ZivletCore

/// The grid (19c §3.2): five 64 pt columns, 8 pt apart both ways.
struct BoxGrid: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(BoxLook.Grid.cell), spacing: BoxLook.Grid.gap, alignment: .top),
            count: BoxLook.Grid.columns)
    }

    /// The cells' frames in the grid's own space, from the tokens.
    static func cells(count: Int) -> [Rect2D] {
        GridSelection.cellFrames(
            count: count, columns: BoxLook.Grid.columns, cell: Double(BoxLook.Grid.cell),
            rowHeight: Double(BoxLook.Grid.rowHeight), gap: Double(BoxLook.Grid.gap))
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: BoxLook.Grid.gap) {
            ForEach(model.items) { BoxCell(item: $0, model: model, press: press) }
        }
        .background(alignment: .topLeading) {
            // Empty space between and below the cells: a click clears the selection, a drag draws a marquee.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { press(.clearSelection) }
                .gesture(
                    DragGesture(minimumDistance: 4).onEnded { drag in
                        press(.marquee(Self.rect(from: drag.startLocation, to: drag.location)))
                    })
        }
    }

    static func rect(from a: CGPoint, to b: CGPoint) -> Rect2D {
        Rect2D(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
