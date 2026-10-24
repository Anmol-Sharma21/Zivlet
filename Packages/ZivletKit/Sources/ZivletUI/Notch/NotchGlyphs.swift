import SwiftUI
import ZivletCore

/// The tab's left end (19b D-NL10): the target's family symbol, or the check mark of a done action.
struct NotchTabIcon: View {
    let icon: TabContent.Icon

    var body: some View {
        switch icon {
        case .family(let family): NotchFamilySymbol(family: family)
        case .action: NotchSymbol(name: NotchSymbol.saved)
        }
    }
}

/// What kind of file is being made, as a white symbol in the tab's 16 pt box.
struct NotchFamilySymbol: View {
    let family: FormatFamily

    var body: some View { NotchSymbol(name: NotchSymbol.name(for: family)) }
}

/// The progress ring (19b §3.3, D-NL11): 16 pt, a 2.5 pt line, fill white on a white 0.3 track, so it meets the 3:1
/// of WCAG 1.4.11 on black, glass and the solid finish.
struct NotchRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(NotchInk.track, lineWidth: NotchLook.Ring.lineWidth)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(NotchInk.primary, style: StrokeStyle(lineWidth: NotchLook.Ring.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(NotchLook.Ring.lineWidth / 2)
        .frame(width: NotchLook.Ring.side, height: NotchLook.Ring.side)
    }
}

/// The stepped glyph of a job of unknown length (D-N7): a quarter arc that moves one of eight steps at a time, so
/// it redraws at most four times a second instead of spinning.
struct NotchSteps: View {
    static let positions = 8
    let step: Int

    var body: some View {
        ZStack {
            Circle().stroke(NotchInk.track, lineWidth: NotchLook.Ring.lineWidth)
            Circle().trim(from: 0, to: 0.25)
                .stroke(NotchInk.primary, style: StrokeStyle(lineWidth: NotchLook.Ring.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(Double(step % Self.positions) * 360 / Double(Self.positions) - 90))
        }
        .padding(NotchLook.Ring.lineWidth / 2)
        .frame(width: NotchLook.Ring.side, height: NotchLook.Ring.side)
    }
}

/// The right end of the tab: the error glyph when anything failed (a shape, not colour alone), else the ring, the
/// stepped glyph or a check mark.
struct NotchStatusGlyph: View {
    let tab: TabContent

    var body: some View {
        if tab.failed {
            NotchSymbol(name: NotchSymbol.failed)
        } else {
            switch tab.ring {
            case .fraction(let value): NotchRing(fraction: value)
            case .step(let step): NotchSteps(step: step)
            case .done: NotchSymbol(name: NotchSymbol.saved)
            }
        }
    }
}

/// One of the island's SF Symbols at tab size, white, in a 16 pt box.
struct NotchSymbol: View {
    static let saved = "checkmark.circle.fill"
    static let failed = "exclamationmark.triangle.fill"
    /// A batch whose jobs were all cancelled: stopped, neither saved nor failed.
    static let cancelled = "stop.circle.fill"

    let name: String

    var body: some View {
        Image(systemName: name).font(NotchLook.Symbol.tab)
            .foregroundStyle(NotchInk.primary)
            .frame(width: NotchLook.Symbol.tabBox, height: NotchLook.Symbol.tabBox)
    }

    /// A done action shows the check mark: the result does not say which action ran (19b D-NL10).
    static func name(for glyph: ToastGlyph) -> String {
        switch glyph {
        case .saved, .action: saved
        case .failed: failed
        case .cancelled: cancelled
        }
    }

    /// The target's format family (19b §3.3).
    static func name(for family: FormatFamily) -> String {
        switch family {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .document: "doc.text"
        case .spreadsheet: "tablecells"
        case .subtitle: "captions.bubble"
        case .archive: "archivebox"
        }
    }
}
