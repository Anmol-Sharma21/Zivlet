import Foundation
import ZivletActions
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

// What the island shows for each display, derived from the items (design/19 §4.3, §5.5).
extension NotchHUDBoard {
    /// The HUD's request: one item rests as its own surface (working → collapsed, a result → toast, a failure after
    /// its toast → collapsed); several rest collapsed. Hover reveals the card or the list. The board never guesses
    /// the height: the host measures it.
    public func request(on display: UInt32) -> IslandRequest? {
        guard let list = items[display], let first = list.first else { return nil }
        let single = list.count == 1
        return IslandRequest(
            client: .hud, display: display, resting: single ? Self.resting(first) : .collapsed,
            hoverSurface: .expanded, closable: single && !first.isWorking)
    }

    public func tab(on display: UInt32) -> TabContent? {
        guard let list = items[display], let first = list.first else { return nil }
        return TabContent(
            icon: Self.icon(first), ring: ring(list), count: list.count > 1 ? NotchHUDCopy.jobs(list.count) : nil,
            failed: list.contains(where: \.isFailure))
    }

    /// The toast's line while the display rests as a toast.
    public func toastLine(on display: UInt32) -> String? {
        guard request(on: display)?.resting == .toast, let item = items[display]?.first else { return nil }
        return Self.line(item)
    }

    /// The toast's text in two styles, as the toast draws it (19b D-NL7).
    public func toastStyledLine(on display: UInt32) -> NotchToastLine? {
        guard request(on: display)?.resting == .toast, let item = items[display]?.first else { return nil }
        switch item.kind {
        case .batch(let snapshot) where snapshot.isFinished:
            return item.isFailure ? NotchHUDCopy.failureLine(snapshot) : NotchHUDCopy.savedLine(snapshot)
        case .batch:
            return NotchToastLine(primary: Self.parts(item))
        case .action(let result):
            return NotchToastLine(primary: [LinePart(text: NotchHUDCopy.action(result), givesWay: false)])
        }
    }

    /// The toast as a screen reader speaks it: separators as words.
    public func toastAccessibilityLabel(on display: UInt32) -> String? {
        toastLine(on: display).map(NotchHUDCopy.spoken)
    }

    public func toastGlyph(on display: UInt32) -> ToastGlyph? {
        guard request(on: display)?.resting == .toast, let item = items[display]?.first else { return nil }
        if item.isFailure { return .failed }
        if item.isCancelled { return .cancelled }
        return item.snapshot == nil ? .action : .saved
    }

    /// The expanded list: failed rows first, at most five.
    public func rows(on display: UInt32) -> [NotchHUDRow] {
        Array(ordered(on: display).prefix(Self.maxRows).map(Self.row))
    }

    /// "+2 more" below the list when it has more than five items.
    public func moreLabel(on display: UInt32) -> String? {
        let count = items[display]?.count ?? 0
        return count > Self.maxRows ? NotchHUDCopy.more(count - Self.maxRows) : nil
    }

    /// The text the expanded island shows, as one spoken value (D-M5a-4): the item's line, or "3 jobs, 1 failed"
    /// and each row.
    public func accessibilityValue(on display: UInt32) -> String {
        let list = ordered(on: display)
        guard list.count > 1 else { return list.first.map { NotchHUDCopy.spoken(Self.spokenLine(Self.row($0))) } ?? "" }
        let failed = list.count(where: \.isFailure)
        let head = [NotchHUDCopy.jobs(list.count)] + (failed > 0 ? [NotchHUDCopy.failedCount(failed)] : [])
        let rows = rows(on: display).map { NotchHUDCopy.spoken(Self.spokenLine($0)) }
        return (head + rows + [moreLabel(on: display)].compactMap { $0 }).joined(separator: ", ")
    }

    /// The items of a display, failed first, otherwise in arrival order.
    func ordered(on display: UInt32) -> [NotchHUDItem] {
        let list = items[display] ?? []
        return list.filter(\.isFailure) + list.filter { !$0.isFailure }
    }

    /// What a display lays out, without progress: when it changes, the island measures its card again.
    struct ItemShape: Equatable {
        let id: NotchHUDItemID
        let working: Bool
        let failure: Bool
        let waits: Bool
    }

    func shapes(on display: UInt32) -> [ItemShape] {
        (items[display] ?? []).map {
            ItemShape(id: $0.id, working: $0.isWorking, failure: $0.isFailure, waits: $0.waits)
        }
    }

    /// Each display's toast line: a new line redraws the island even when its shape stays.
    var toastLines: [UInt32: String] {
        Dictionary(uniqueKeysWithValues: displays.compactMap { id in toastLine(on: id).map { (id, $0) } })
    }

    func item(_ id: NotchHUDItemID) -> NotchHUDItem? { items.values.joined().first { $0.id == id } }

    func display(of id: NotchHUDItemID) -> UInt32? { items.first { $0.value.contains { $0.id == id } }?.key }

    /// One working item: its ring or stepped glyph. Several: the mean over the working ones, or the stepped glyph
    /// when none of them knows its length. Nothing working: a check mark.
    private func ring(_ list: [NotchHUDItem]) -> TabContent.Ring {
        let working = list.filter(\.isWorking)
        guard !working.isEmpty else { return .done }
        let since = working.compactMap(\.indeterminateSince)
        if since.count == working.count, let first = since.min() {
            return .step(steps(since: first) % Self.stepCount)
        }
        let fractions = working.compactMap { $0.snapshot?.fraction }
        return .fraction(fractions.reduce(0, +) / Double(fractions.count))
    }

    private static func resting(_ item: NotchHUDItem) -> IslandSurface {
        item.isWorking || item.waits ? .collapsed : .toast
    }

    private static func icon(_ item: NotchHUDItem) -> TabContent.Icon {
        guard let snapshot = item.snapshot else { return .action }
        return .family(FormatRegistry.standard.format(snapshot.target).family)
    }

    /// The one-line form of an item: "Saved photo.jpg · 2.1 MB → 640 KB", the failure's title and reason, the
    /// action's toast, or the working line.
    static func line(_ item: NotchHUDItem) -> String { LinePart.joined(parts(item)) }

    static func parts(_ item: NotchHUDItem) -> [LinePart] {
        switch item.kind {
        case .batch(let snapshot):
            guard snapshot.isFinished else { return HUDCopy.workingParts(snapshot) }
            return item.isFailure ? NotchHUDCopy.failureParts(snapshot) : NotchHUDCopy.savedParts(snapshot)
        case .action(let result):
            return [LinePart(text: NotchHUDCopy.action(result), givesWay: false)]
        }
    }

    static func row(_ item: NotchHUDItem) -> NotchHUDRow {
        switch item.kind {
        case .batch(let snapshot) where !snapshot.isFinished:
            return NotchHUDRow(
                id: item.id, title: HUDCopy.title(target: snapshot.target), detail: HUDCopy.working(snapshot),
                status: .working(snapshot.isIndeterminate ? nil : snapshot.fraction),
                line: NotchHUDCopy.workingTitle(snapshot), summary: NotchHUDCopy.percent(snapshot) ?? "")
        case .batch(let snapshot):
            let shown = BatchPresentation.make(snapshot)
            let styled = item.isFailure ? NotchHUDCopy.failureLine(snapshot) : NotchHUDCopy.savedLine(snapshot)
            return NotchHUDRow(
                id: item.id, title: shown.title, detail: ResultCardModel.sizeLine(snapshot) ?? shown.subtitle,
                status: Self.finishedStatus(item), line: Self.rowLine(styled, failed: item.isFailure),
                summary: item.isFailure ? NotchHUDCopy.failedStatus : styled.secondary ?? "")
        case .action(let result):
            let detail = result.card?.lines.joined(separator: " · ") ?? ""
            let failed = result.card != nil
            return NotchHUDRow(
                id: item.id, title: NotchHUDCopy.action(result), detail: detail, status: failed ? .failed : .action,
                summary: failed ? NotchHUDCopy.failedStatus : "")
        }
    }

    /// A saved row says "Saved photo.jpg"; a failed one names its file beside "Failed", since the whole reason does
    /// not fit on one line next to its buttons (the card and the spoken list keep the reason).
    private static func rowLine(_ styled: NotchToastLine, failed: Bool) -> String {
        guard failed, let name = styled.secondary, !name.isEmpty else { return LinePart.joined(styled.primary) }
        return name
    }

    private static func finishedStatus(_ item: NotchHUDItem) -> NotchHUDRow.Status {
        if item.isFailure { return .failed }
        return item.isCancelled ? .cancelled : .saved
    }

    private static func spokenLine(_ row: NotchHUDRow) -> String {
        row.detail.isEmpty ? row.title : "\(row.title) · \(row.detail)"
    }
}
