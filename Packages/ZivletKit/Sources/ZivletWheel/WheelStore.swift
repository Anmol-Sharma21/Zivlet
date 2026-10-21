import Observation
import ZivletWheelCore

/// Observable holder of the immutable `WheelModel` (02 §7.7). It replaces the model only when a hit changes the
/// highlight, so SwiftUI re-renders on slot changes, not on every `draggingUpdated`.
@Observable
public final class WheelStore {
    public private(set) var model: WheelModel?
    public private(set) var appearance = WheelAppearance(
        theme: .glass, palette: AccentPalette(base: RGB(r: 0, g: 0.48, b: 1)), reduceMotion: false)
    public private(set) var isExpanded = false
    /// Bumped on each reject; drives the shake animation.
    public private(set) var rejectCount = 0
    /// Bumped by each `present`; the view keys its expand task on it (03a §2.7 intro).
    public private(set) var presentation = 0
    @ObservationIgnored private var expansionPending = false
    private var notice: String?
    private var emptyMessage: String?

    @ObservationIgnored private let feedback: any WheelFeedback
    @ObservationIgnored private let noticeDuration: Duration
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    public init(feedback: any WheelFeedback, noticeDuration: Duration = .milliseconds(1_200)) {
        self.feedback = feedback
        self.noticeDuration = noticeDuration
    }

    public var theme: WheelTheme { appearance.theme }
    /// Reject notice first, else the empty-state reason.
    public var pillText: String? { notice ?? emptyMessage }

    /// Shows a new wheel collapsed. The on-screen view calls `expandIfPending` once it has rendered that state, so
    /// the intro always animates from the collapsed scale.
    public func present(_ model: WheelModel, emptyMessage: String?, appearance: WheelAppearance) {
        clearNotice()
        self.model = model
        self.emptyMessage = emptyMessage
        self.appearance = appearance
        isExpanded = false
        presentation += 1
        expansionPending = true
    }

    /// Expands at once, without waiting for the view (pre-warm, tests).
    public func expand() {
        expansionPending = false
        isExpanded = true
    }

    /// Expands only the presentation the view rendered, once, and never after `cancelExpansion` or `dismiss`.
    public func expandIfPending(_ presentation: Int) {
        guard expansionPending, presentation == self.presentation, model != nil else { return }
        expand()
    }

    /// The wheel is hiding: a view task that has not run yet must not expand it.
    public func cancelExpansion() { expansionPending = false }

    public func pointer(_ hit: HitResult) {
        guard let model else { return }
        let next = model.applying(hit)
        guard next != model else { return }
        self.model = next
        if next.highlighted != nil { feedback.highlightChanged() }
    }

    public func switchTo(_ model: WheelModel, emptyMessage: String?) {
        clearNotice()
        self.model = model
        self.emptyMessage = emptyMessage
        feedback.modeSwitched()
    }

    /// Another wheel refused the items: shake and show why for 1.2 s; the current wheel stays (03a §1.4 T12).
    public func reject(message: String) {
        notice = message
        rejectCount += 1
        feedback.rejected()
        noticeTask?.cancel()
        noticeTask = Task { [weak self, noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    public func dropAccepted() { feedback.dropAccepted() }

    public func dismiss() {
        clearNotice()
        model = nil
        emptyMessage = nil
        isExpanded = false
        expansionPending = false
    }

    private func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }
}
