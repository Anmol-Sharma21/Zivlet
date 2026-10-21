import SwiftUI
import ZivletRuntime

/// Working: target, the current item's line, a bar (indeterminate while the length is unknown), Cancel. Finished:
/// the result card.
struct ResultHUDView: View {
    let model: HUDModel
    let cancel: () -> Void
    let act: (ResultCardModel.Button) -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                if snapshot.isFinished {
                    ResultCard(model: ResultCardModel(snapshot), state: model.card, act: act)
                } else {
                    working(snapshot)
                }
            }
        }
        .onHover(perform: hover)
    }

    private func working(_ snapshot: BatchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HUDCopy.title(target: snapshot.target)).font(.headline).lineLimit(1)
            Text(HUDCopy.working(snapshot)).font(.callout).foregroundStyle(HUDInk.secondary).lineLimit(1)
                .truncationMode(.middle)
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
        .padding(14)
        .frame(width: HUDLayout.size.width, height: HUDLayout.size.height, alignment: .topLeading)
        .hudGlass()
    }
}
