import SwiftUI
import ZivletRuntime

/// A working batch without a surface: target, the current item's line, a bar (indeterminate while the length is
/// unknown), Cancel. `ResultHUDView` puts it on the glass panel; the notch island on its black card.
struct WorkingContent: View {
    let snapshot: BatchSnapshot
    /// The width of the content itself, inside the surface's padding.
    let width: CGFloat
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HUDCopy.title(target: snapshot.target)).font(.headline).lineLimit(1)
            PartedLine(parts: HUDCopy.workingParts(snapshot)).font(.callout).foregroundStyle(HUDInk.secondary)
            if snapshot.isIndeterminate {
                ProgressView().progressViewStyle(.linear)
            } else {
                ProgressView(value: snapshot.fraction)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
            }
            .controlSize(.small)
        }
        .frame(width: width, alignment: .topLeading)
    }
}
