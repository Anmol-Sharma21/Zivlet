import AppKit
import SwiftUI
import ZivletCore
import ZivletRuntime

/// What the HUD view renders; replaced whole on every snapshot.
@Observable
final class HUDModel {
    var presentation: BatchPresentation?
    var undoMessage: String?
    /// The last undo left files the Trash refused, so Undo stays available.
    var undoCanRetry = false
}

/// What an undo said, and whether pressing Undo again can still help.
struct UndoReply {
    let message: String
    let canRetry: Bool
}

/// The conversion HUD (01-prd FR-14, M3 subset of P1-40/P1-41): a non-activating glass panel near the drop point with
/// progress and Cancel while working, then Reveal in Finder and Undo, or the failure in Zivlet's words. With several
/// batches at once, `HUDBoard` picks the one on screen (a finished failure stays until closed) and every button acts
/// on that batch.
final class ResultHUD {
    static let size = NSSize(width: 360, height: 132)
    static let successLinger = Duration.seconds(6)

    var onCancel: (BatchID) -> Void = { _ in }
    var onReveal: ([URL]) -> Void = { _ in }
    /// Undoes the shown batch and returns the sentence to show in its place.
    var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }

    private let model = HUDModel()
    private let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: ResultHUD.size), styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: true)
    private var board = HUDBoard()
    private var renderedBatch: BatchID?
    private var anchor: CGPoint?
    private var hideTask: Task<Void, Never>?

    init() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = ResultHUDView(
            model: model, cancel: { [weak self] in self?.cancel() }, reveal: { [weak self] in self?.reveal() },
            undo: { [weak self] in self?.undo() }, close: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
    }

    /// Remembers where the drop happened (nil = centre of the main screen) for the next batch.
    func prepare(near point: CGPoint?) {
        anchor = point
    }

    func show(_ snapshot: BatchSnapshot) {
        board = board.updating(snapshot)
        render()
    }

    /// Close: the shown batch is dismissed and the next one, if any, takes its place.
    func hide() {
        if let batch = board.shown?.batch { board = board.dismissing(batch) }
        render()
    }

    private func render() {
        hideTask?.cancel()
        guard let shown = board.shown else {
            renderedBatch = nil
            panel.orderOut(nil)
            return
        }
        if shown.batch != renderedBatch {
            model.undoMessage = nil
            model.undoCanRetry = false
            renderedBatch = shown.batch
        }
        model.presentation = BatchPresentation.make(shown)
        if !panel.isVisible { place() }
        panel.orderFrontRegardless()
        if shown.isFinished, model.presentation?.phase == .succeeded, model.undoMessage == nil { linger(shown.batch) }
    }

    /// A success leaves after a while, but only while it is still the batch on screen.
    private func linger(_ batch: BatchID) {
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.successLinger)
            } catch {
                return  // re-rendered or closed meanwhile
            }
            guard let self else { return }
            self.board = self.board.expiring(batch)
            self.render()
        }
    }

    private func cancel() {
        if let batch = board.shown?.batch { onCancel(batch) }
    }

    private func reveal() {
        onReveal(board.shown?.outputs.map(\.url) ?? [])
    }

    private func undo() {
        guard let batch = board.shown?.batch else { return }
        hideTask?.cancel()
        Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            guard let self, self.board.shown?.batch == batch else { return }
            self.model.undoMessage = reply.message
            self.model.undoCanRetry = reply.canRetry
        }
    }

    private func place() {
        if let origin = HUDPlacement.origin(near: anchor, size: Self.size) { panel.setFrameOrigin(origin) }
    }
}

struct ResultHUDView: View {
    let model: HUDModel
    let cancel: () -> Void
    let reveal: () -> Void
    let undo: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let shown = model.presentation {
                Text(shown.title).font(.headline).lineLimit(1)
                Text(shown.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let fraction = shown.fraction { ProgressView(value: fraction) }
                ForEach(shown.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if let message = model.undoMessage ?? shown.detail {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                buttons(shown)
            }
        }
        .padding(14)
        .frame(width: ResultHUD.size.width, height: ResultHUD.size.height, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func buttons(_ shown: BatchPresentation) -> some View {
        HStack {
            Spacer()
            if shown.canCancel { Button("Cancel", action: cancel) }
            if shown.canUndo, model.undoMessage == nil || model.undoCanRetry { Button("Undo", action: undo) }
            if shown.canReveal { Button("Reveal in Finder", action: reveal) }
            if !shown.canCancel { Button("Close", action: close).keyboardShortcut(.cancelAction) }
        }
        .controlSize(.small)
    }
}
