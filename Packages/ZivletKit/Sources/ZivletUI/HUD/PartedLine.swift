import SwiftUI

/// One line of text in parts (`LinePart`): the parts that give way lose their middle first, the others keep their
/// width, so "Saved holi…day.mov · 2.1 MB → 640 KB" keeps the sizes and the extension.
struct PartedLine: View {
    let parts: [LinePart]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .lineLimit(1)
                    .truncationMode(part.givesWay ? .middle : .tail)
                    .layoutPriority(part.givesWay ? 0 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LinePart.joined(parts))
    }
}
