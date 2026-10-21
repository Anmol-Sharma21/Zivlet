import SwiftUI
import ZivletRuntime

/// Working: target, the current item's line, a bar (indeterminate while the length is unknown), Cancel. Finished:
/// the result in Zivlet's words with Undo, Reveal and Close.
struct ResultHUDView: View {
    let model: HUDModel
    let cancel: () -> Void
    let reveal: () -> Void
    let undo: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = model.snapshot {
                if snapshot.isFinished { finished(BatchPresentation.make(snapshot)) } else { working(snapshot) }
            }
        }
        .padding(14)
        .frame(width: HUDLayout.size.width, alignment: .topLeading)
        .frame(minHeight: HUDLayout.size.height, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder private func working(_ snapshot: BatchSnapshot) -> some View {
        Text(HUDCopy.title(target: snapshot.target)).font(.headline).lineLimit(1)
        Text(HUDCopy.working(snapshot)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
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

    @ViewBuilder private func finished(_ shown: BatchPresentation) -> some View {
        Text(shown.title).font(.headline).lineLimit(1)
        Text(shown.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        ForEach(shown.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        if let message = model.undoMessage ?? shown.detail {
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        HStack {
            Spacer()
            if shown.canUndo, model.undoMessage == nil || model.undoCanRetry { Button("Undo", action: undo) }
            if shown.canReveal { Button("Reveal in Finder", action: reveal) }
            Button("Close", action: close).keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
    }
}
